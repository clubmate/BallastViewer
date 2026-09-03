import Foundation
import HuggingFace
import Observation

/// U49: which vision-language models the app knows, which is selected, and
/// what state each is in on disk. Models live in the standard Hugging Face
/// cache (`~/.cache/huggingface/hub`), so nothing is bundled and a model
/// already fetched by another tool is simply reused. Any MLX-converted
/// repository whose architecture mlx-swift-lm implements can be added by
/// its Hugging Face id — swapping to next year's model is a text field, not
/// an app update.
@MainActor @Observable
final class VLMModelStore {
    struct ModelInfo: Identifiable, Hashable, Codable, Sendable {
        /// The Hugging Face repository id ("owner/name") — the identity.
        var id: String
        var title: String
        var sizeGB: Double?
        var note: String
        var builtIn: Bool
    }

    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    /// Curated starting points. Sizes are the 4-bit MLX weights on disk.
    nonisolated static let presets: [ModelInfo] = [
        ModelInfo(
            id: "mlx-community/Qwen3.5-9B-4bit", title: "Qwen3.5 9B", sizeGB: 6.0,
            note: "Best answers — needs 16 GB of memory or more.", builtIn: true
        ),
        ModelInfo(
            id: "mlx-community/Qwen3.5-4B-4bit", title: "Qwen3.5 4B", sizeGB: 3.1,
            note: "Good balance of accuracy and speed; fine with 8 GB.", builtIn: true
        ),
        ModelInfo(
            id: "mlx-community/Qwen3.5-2B-4bit", title: "Qwen3.5 2B", sizeGB: 1.8,
            note: "Fastest; noticeably more mistakes on counting and age.", builtIn: true
        ),
        ModelInfo(
            id: "mlx-community/Qwen3-VL-8B-Instruct-4bit", title: "Qwen3-VL 8B", sizeGB: 5.8,
            note: "Previous generation, well proven.", builtIn: true
        ),
        ModelInfo(
            id: "mlx-community/gemma-3-4b-it-4bit", title: "Gemma 3 4B", sizeGB: 3.2,
            note: "Google's model; a second opinion with a different training.", builtIn: true
        ),
    ]

    /// Architectures mlx-swift-lm's VLM registry implements (its
    /// `model_type` keys) — what "Add model" checks a repository against.
    nonisolated static let supportedModelTypes: Set<String> = [
        "qwen2_vl", "qwen2_5_vl", "qwen3_vl", "qwen3_5", "qwen3_5_moe", "gemma3", "gemma4",
        "gemma4_unified", "idefics3", "smolvlm", "fastvlm", "llava_qwen2", "paligemma", "pixtral",
        "mistral3", "lfm2_vl", "lfm2-vl", "glm_ocr",
    ]

    private static let customKey = "vlmCustomModels"
    private static let selectedKey = "vlmSelectedModel"

    private(set) var custom: [ModelInfo]
    var selectedId: String {
        didSet { UserDefaults.standard.set(selectedId, forKey: Self.selectedKey) }
    }
    private(set) var states: [String: State] = [:]
    /// Error of the last "Add model" attempt, shown under the field.
    private(set) var addError: String?
    private(set) var isValidatingCustom = false

    let service = VLMService()

    init() {
        let data = UserDefaults.standard.data(forKey: Self.customKey)
        custom = data.flatMap { try? JSONDecoder().decode([ModelInfo].self, from: $0) } ?? []
        selectedId = UserDefaults.standard.string(forKey: Self.selectedKey) ?? Self.presets[0].id
        refreshStates()
    }

    var models: [ModelInfo] { Self.presets + custom }

    var selected: ModelInfo? { models.first { $0.id == selectedId } }

    func state(of id: String) -> State { states[id] ?? .notDownloaded }

    /// The selected model is on disk and can be loaded.
    var isSelectedReady: Bool { state(of: selectedId) == .ready }

    /// A snapshot directory with a config.json = downloaded. Downloads in
    /// flight keep their progress state.
    func refreshStates() {
        for model in models {
            if case .downloading = states[model.id] { continue }
            states[model.id] = Self.isInstalled(model.id) ? .ready : .notDownloaded
        }
    }

    nonisolated static func isInstalled(_ id: String) -> Bool {
        guard let repo = Repo.ID(rawValue: id) else { return false }
        let snapshots = HubCache.default.snapshotsDirectory(repo: repo, kind: .model)
        guard let revisions = try? FileManager.default.contentsOfDirectory(atPath: snapshots.path) else {
            return false
        }
        return revisions.contains { revision in
            FileManager.default.fileExists(
                atPath: snapshots.appendingPathComponent(revision).appendingPathComponent("config.json").path
            )
        }
    }

    // MARK: Download / remove

    func download(_ id: String) {
        if case .downloading = state(of: id) { return }
        states[id] = .downloading(0)
        Task {
            do {
                _ = try await HubBridge(hub: HubClient()).download(
                    id: id, revision: "main", matching: VLMService.downloadPatterns, useLatest: false
                ) { [weak self] progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in self?.states[id] = .downloading(fraction) }
                }
                states[id] = Self.isInstalled(id) ? .ready : .failed("The download finished but no config.json arrived.")
            } catch {
                states[id] = .failed(error.localizedDescription)
            }
        }
    }

    /// Deletes the model's files from the cache (after unloading it).
    func remove(_ id: String) {
        guard let repo = Repo.ID(rawValue: id) else { return }
        Task {
            await service.unload()
            let directory = HubCache.default.repoDirectory(repo: repo, kind: .model)
            try? FileManager.default.removeItem(at: directory)
            states[id] = .notDownloaded
        }
    }

    // MARK: Custom models

    struct RepositoryError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Validates a Hugging Face repository id and adds it to the list: it
    /// must exist, be an MLX conversion (safetensors + config.json) of an
    /// architecture the runtime implements.
    func addCustom(repositoryId raw: String) {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        addError = nil
        guard !id.isEmpty else { return }
        guard !models.contains(where: { $0.id == id }) else {
            addError = "That model is already in the list."
            return
        }
        guard id.split(separator: "/").count == 2 else {
            addError = "Enter the repository id as owner/name, e.g. mlx-community/Qwen3.5-4B-4bit."
            return
        }
        isValidatingCustom = true
        Task {
            defer { isValidatingCustom = false }
            do {
                let info = try await Self.inspect(repositoryId: id)
                custom.append(info)
                persistCustom()
                refreshStates()
            } catch {
                addError = error.localizedDescription
            }
        }
    }

    func removeCustom(_ id: String) {
        custom.removeAll { $0.id == id }
        persistCustom()
        if selectedId == id { selectedId = Self.presets[0].id }
    }

    private func persistCustom() {
        UserDefaults.standard.set(try? JSONEncoder().encode(custom), forKey: Self.customKey)
    }

    /// Reads the repository's metadata from the Hub API: model_type, file
    /// list and sizes.
    nonisolated static func inspect(repositoryId id: String) async throws -> ModelInfo {
        var request = URLRequest(url: URL(string: "https://huggingface.co/api/models/\(id)?blobs=true")!)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RepositoryError("No response from Hugging Face.") }
        guard http.statusCode != 404 else { throw RepositoryError("No repository “\(id)” on Hugging Face.") }
        guard http.statusCode == 200 else { throw RepositoryError("Hugging Face answered HTTP \(http.statusCode).") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RepositoryError("Unexpected answer from Hugging Face.")
        }
        let modelType = ((json["config"] as? [String: Any])?["model_type"] as? String) ?? ""
        guard supportedModelTypes.contains(modelType) else {
            throw RepositoryError(
                modelType.isEmpty
                    ? "The repository has no model config — it is not a converted model."
                    : "Architecture “\(modelType)” is not supported by the on-device runtime."
            )
        }
        let siblings = (json["siblings"] as? [[String: Any]]) ?? []
        let names = siblings.compactMap { $0["rfilename"] as? String }
        guard names.contains(where: { $0.hasSuffix(".safetensors") }) else {
            throw RepositoryError("The repository carries no safetensors weights — look for an MLX conversion (often under mlx-community).")
        }
        let bytes = siblings.reduce(0.0) { $0 + (($1["size"] as? Double) ?? 0) }
        return ModelInfo(
            id: id,
            title: String(id.split(separator: "/").last ?? Substring(id)),
            sizeGB: bytes > 0 ? (bytes / 1e9 * 10).rounded() / 10 : nil,
            note: "Added by you (\(modelType)).",
            builtIn: false
        )
    }
}
