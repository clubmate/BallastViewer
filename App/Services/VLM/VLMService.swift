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
        container = nil
        loadedModelId = nil
        MLX.GPU.clearCache()
    }

    /// One questionnaire, one photo → the model's raw reply (JSON, parsed by
    /// `VLMAnswerParser`). Greedy decoding, thinking off: the same photo and
    /// prompt give the same reply every run.
    func answer(image: CGImage, systemPrompt: String, userPrompt: String) async throws -> String {
        guard let container else { throw GenerationError("No model is loaded.") }
        let input = UserInput(
            chat: [
                .system(systemPrompt),
                .user(userPrompt, images: [.ciImage(CIImage(cgImage: image))]),
            ],
            processing: .init(resize: CGSize(width: Self.imageLongEdge, height: Self.imageLongEdge)),
            additionalContext: ["enable_thinking": false]
        )
        let prepared = try await container.prepare(input: input)
        let stream = try await container.generate(
            input: prepared, parameters: GenerateParameters(maxTokens: 256, temperature: 0)
        )
        var reply = ""
        for await generation in stream {
            if let chunk = generation.chunk { reply += chunk }
        }
        return reply
    }
}
