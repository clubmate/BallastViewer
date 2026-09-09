import BallastCore
import CoreGraphics
import CoreImage
import Foundation
import HuggingFace
import MLX
import MLXLMCommon
import MLXVLM

/// U49: the vision-language model behind an actor — one loaded model at a
/// time, every generation serialized through it (the GPU is one resource,
/// and MLX's lazy evaluation is happiest single-file). Loading pulls the
/// weights from the Hugging Face cache (downloading first if needed) and
/// keeps them in memory until `unload()`.
actor VLMService {
    private var container: ModelContainer?
    private(set) var loadedModelId: String?

    /// U57: the KV cache of the system turn (system prompt + questions),
    /// computed once per run and reused for every photo — the photo and
    /// the answer are the only tokens the model still has to process.
    /// Rebuilt whenever the instruction text changes (a different subset of
    /// questionnaires, edited wording).
    private var prefix: PromptPrefix?

    /// Everything a cached prefix consists of: the token ids it was built
    /// from (verified against every new prompt), the warmed KV cache and
    /// the model state that belongs with it (Qwen's M-RoPE anchor).
    final class PromptPrefix {
        let key: String
        let tokens: [Int]
        let cache: [KVCache]
        let state: LMOutput.State?

        init(key: String, tokens: [Int], cache: [KVCache], state: LMOutput.State?) {
            self.key = key
            self.tokens = tokens
            self.cache = cache
            self.state = state
        }
    }

    /// Carries non-Sendable MLX values into and out of `ModelContainer.perform`
    /// — the actor serializes every use, nothing is shared.
    struct Carried<T>: @unchecked Sendable {
        let value: T
    }

    /// Timing of the last generation — printed by the test hook.
    private(set) var lastInfo: (promptTokens: Int, promptSeconds: Double, generatedTokens: Int, generateSeconds: Double, prefixTokens: Int)?

    /// Test hook: off = every photo carries the full prompt (the pre-U57 cost).
    private var prefixCaching = true
    func setPrefixCaching(_ enabled: Bool) {
        prefixCaching = enabled
        if !enabled { prefix = nil }
    }

    /// Files a model needs — weights, configs, tokenizer, chat template.
    static let downloadPatterns = ["*.safetensors", "*.json", "*.jinja", "*.txt", "*.model", "*.tiktoken"]

    /// Long edge the photo is sent at. Qwen-class models tile the image in
    /// 16-px patches; 768 keeps a portrait's face and a group's headcount
    /// readable without paying for detail the questions never ask about.
    static let imageLongEdge = 768

    struct GenerationError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Loads `modelId` (no-op when it is already the loaded one).
    func load(modelId: String, progress: @Sendable @escaping (Double) -> Void) async throws {
        if loadedModelId == modelId, container != nil { return }
        unload()
        // MLX's buffer cache would otherwise hold on to freed activations
        // between photos; the app has thumbnails to keep in RAM too.
        MLX.GPU.set(cacheLimit: 32 * 1024 * 1024)
        let loaded = try await loadModelContainer(
            from: HubBridge(hub: HubClient()),
            using: TransformersLoader(),
            configuration: ModelConfiguration(id: modelId, extraEOSTokens: ["<|im_end|>"]),
            progressHandler: { progress($0.fractionCompleted) }
        )
        container = loaded
        loadedModelId = modelId
    }

    func unload() {
        prefix = nil
        container = nil
        loadedModelId = nil
        MLX.GPU.clearCache()
    }

    /// U57: one photo against a fixed instruction text (system prompt +
    /// questions), the photo alone in the user turn. The instruction text's
    /// KV cache is built on first use and reused for every following photo
    /// with the same text: only the image tokens and the answer are computed
    /// per photo. Falls back to a plain prompt when the model's template has
    /// no vision-start marker to cut at (then nothing is cached, nothing is
    /// lost). Greedy decoding, like `answer(image:systemPrompt:userPrompt:)`.
    func answer(
        image: CGImage, instructions: String,
        thinking: Bool = false, fullResolution: Bool = false, maxTokens: Int = 256
    ) async throws -> String {
        guard let container else { throw GenerationError("No model is loaded.") }
        let input = UserInput(
            chat: [
                .system(instructions),
                .user(VLMPrompt.photoTurn, images: [.ciImage(CIImage(cgImage: image))]),
            ],
            processing: .init(
                resize: fullResolution ? nil : CGSize(width: Self.imageLongEdge, height: Self.imageLongEdge)
            ),
            additionalContext: ["enable_thinking": thinking]
        )
        let parameters = GenerateParameters(maxTokens: thinking ? Self.thinkingMaxTokens : maxTokens, temperature: 0)
        let key = instructions + "\u{1E}" + (thinking ? "think" : "")
        let carried = Carried(value: (input: input, prefix: prefix, caching: prefixCaching))
        let result = try await container.perform(values: carried) { context, carried -> Carried<(String, GenerateStopReason?, PromptPrefix?, GenerateCompletionInfo?, Int)> in
            let full = try await context.processor.prepare(input: carried.value.input)
            var prefix = carried.value.prefix
            var suffix = full
            var caches: [KVCache]?
            var state: LMOutput.State?
            var prefixLength = 0
            if carried.value.caching, let visionStart = context.tokenizer.convertTokenToId("<|vision_start|>") {
                // The processor hands the tokens back as [1, L]; work on the
                // flat id list and rebuild [1, n] arrays (prefill wants the
                // batch axis).
                let ids = full.text.tokens.asType(.int32).asArray(Int32.self).map { Int($0) }
                if let cut = ids.firstIndex(of: visionStart), cut > 0 {
                    let prefixIds = Array(ids[..<cut])
                    if prefix == nil || prefix!.key != key || prefix!.tokens != prefixIds {
                        prefix = Self.buildPrefix(
                            key: key, tokens: prefixIds, tokenArray: MLXArray(prefixIds).expandedDimensions(axis: 0),
                            context: context, parameters: parameters
                        )
                    }
                    if let prefix {
                        suffix = LMInput(
                            text: .init(tokens: MLXArray(Array(ids[cut...])).expandedDimensions(axis: 0)),
                            image: full.image
                        )
                        caches = prefix.cache.map { $0.copy() }
                        state = prefix.state
                        prefixLength = cut
                    }
                }
            }
            // The iterator takes the warmed cache copies and the state that
            // belongs with them (the M-RoPE anchor of the prefix); with a
            // fresh cache it is the ordinary full-prompt generation.
            let iterator = try TokenIterator(
                input: suffix, model: context.model, cache: caches, state: state, parameters: parameters
            )
            let stream = MLXLMCommon.generate(input: suffix, context: context, iterator: iterator)
            var reply = ""
            var stopReason: GenerateStopReason?
            var info: GenerateCompletionInfo?
            for await generation in stream {
                if let chunk = generation.chunk { reply += chunk }
                if let completion = generation.info {
                    stopReason = completion.stopReason
                    info = completion
                }
            }
            return Carried(value: (reply, stopReason, prefix, info, prefixLength))
        }
        let (reply, stopReason, newPrefix, info, prefixLength) = result.value
        prefix = newPrefix
        if let info {
            lastInfo = (info.promptTokenCount, info.promptTime, info.generationTokenCount, info.generateTime, prefixLength)
        }
        if Task.isCancelled || stopReason == .cancelled { throw CancellationError() }
        return reply
    }

    /// Prefills `tokenArray` (the prompt up to the image) into a fresh cache.
    /// Nil when the model hands the prompt back for stepping instead of
    /// prefilling it (no model the app ships does; the caller then sends the
    /// full prompt) or when the prefill fails.
    private static func buildPrefix(
        key: String, tokens: [Int], tokenArray: MLXArray, context: ModelContext, parameters: GenerateParameters
    ) -> PromptPrefix? {
        do {
            let cache = try context.model.newCache(parameters: parameters)
            let result = try context.model.prepare(
                LMInput(text: .init(tokens: tokenArray)), cache: cache, state: nil, windowSize: parameters.prefillStepSize
            )
            guard case .logits(let output) = result else { return nil }
            eval(output.logits)
            eval(cache.flatMap(\.state))
            return PromptPrefix(key: key, tokens: tokens, cache: cache, state: output.state)
        } catch {
            return nil
        }
    }

    /// Token budget with thinking on: the trace comes before the answer and
    /// runs a few hundred to a couple of thousand tokens on a hard photo.
    static let thinkingMaxTokens = 4096

    /// One questionnaire, one photo → the model's raw reply (JSON, parsed by
    /// `VLMAnswerParser`). Greedy decoding: the same photo, prompt and
    /// settings give the same reply every run. `thinking` lets the model
    /// reason in a `<think>` block first (slower, sometimes more careful);
    /// `fullResolution` sends the image as decoded instead of capped at
    /// `imageLongEdge` (the processor itself allows up to 16 MP). `maxTokens`
    /// raises the 256-token answer budget (free questions answer in prose);
    /// with thinking on the thinking budget applies regardless.
    func answer(
        image: CGImage, systemPrompt: String, userPrompt: String,
        thinking: Bool = false, fullResolution: Bool = false, maxTokens: Int? = nil
    ) async throws -> String {
        guard let container else { throw GenerationError("No model is loaded.") }
        let input = UserInput(
            chat: [
                .system(systemPrompt),
                .user(userPrompt, images: [.ciImage(CIImage(cgImage: image))]),
            ],
            processing: .init(
                resize: fullResolution ? nil : CGSize(width: Self.imageLongEdge, height: Self.imageLongEdge)
            ),
            additionalContext: ["enable_thinking": thinking]
        )
        let prepared = try await container.prepare(input: input)
        let stream = try await container.generate(
            input: prepared,
            parameters: GenerateParameters(maxTokens: thinking ? Self.thinkingMaxTokens : (maxTokens ?? 256), temperature: 0)
        )
        var reply = ""
        var stopReason: GenerateStopReason?
        for await generation in stream {
            if let chunk = generation.chunk { reply += chunk }
            if let info = generation.info { stopReason = info.stopReason }
        }
        // A cancelled stream ends quietly with whatever was produced — that
        // must never be mistaken for an answer (and never be cached).
        if Task.isCancelled || stopReason == .cancelled { throw CancellationError() }
        return reply
    }
}
