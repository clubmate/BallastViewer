import Foundation
import HuggingFace
import MLXLMCommon
import Tokenizers

// U49: the two adapters mlx-swift-lm needs to fetch a model from Hugging
// Face and read its tokenizer — written out instead of using the
// `MLXHuggingFace` macros, which Xcode refuses to build unless the macro
// plugin is trusted on every machine (and in CI).

/// `HubClient` (swift-huggingface) as an MLXLMCommon `Downloader`. Files
/// land in the standard Hugging Face cache (`~/.cache/huggingface/hub`, or
/// `$HF_HOME`), shared with every other tool that uses it — a model the
/// user already has is not downloaded twice.
struct HubBridge: Downloader {
    let hub: HubClient

    struct InvalidRepository: LocalizedError {
        let id: String
        var errorDescription: String? { "“\(id)” is not a valid Hugging Face repository id (expected owner/name)." }
    }

    func download(
        id: String, revision: String?, matching patterns: [String], useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repo = Repo.ID(rawValue: id) else { throw InvalidRepository(id: id) }
        return try await hub.downloadSnapshot(
            of: repo, revision: revision ?? "main", matching: patterns,
            progressHandler: { @MainActor progress in progressHandler(progress) }
        )
    }
}

/// swift-transformers `AutoTokenizer` as an MLXLMCommon `TokenizerLoader`.
struct TransformersLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}

struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
