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
        /// Not installed, but an interrupted download left this many bytes
        /// in the cache — the next Download continues from there.
        case partial(Int64)
        case downloading(DownloadProgress)
        case ready
        case failed(String)
    }

    struct DownloadProgress: Equatable {
        var bytes: Int64
        var total: Int64
        /// Smoothed transfer rate; nil until the first second of data.
        var bytesPerSecond: Double?

        var fraction: Double { total > 0 ? min(1, Double(bytes) / Double(total)) : 0 }
        var secondsLeft: TimeInterval? {
            guard let bytesPerSecond, bytesPerSecond > 0, total > bytes else { return nil }
            return Double(total - bytes) / bytesPerSecond
        }
    }

    /// Curated starting points (user decision 2026-09-04: the Qwen3.5 sizes
    /// from 27B down to 2B — anything else by id). Sizes are the 4-bit MLX
    /// weights on disk.
    nonisolated static let presets: [ModelInfo] = [
        ModelInfo(
            id: "mlx-community/Qwen3.5-27B-4bit", title: "Qwen3.5 27B", sizeGB: 16.1,
            note: "The largest that fits 24 GB — leaves little room for anything else while it runs.", builtIn: true
        ),
        ModelInfo(
            id: "mlx-community/Qwen3.5-9B-4bit", title: "Qwen3.5 9B", sizeGB: 6.0,
            note: "Best answers — needs 16 GB of memory or more.", builtIn: true
        ),
        ModelInfo(
            id: "mlx-community/Qwen3.5-2B-4bit", title: "Qwen3.5 2B", sizeGB: 1.8,
            note: "Fastest; noticeably more mistakes on counting and age.", builtIn: true
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
    /// The sensible default on a 16–24 GB Mac.
    nonisolated static let defaultModelId = "mlx-community/Qwen3.5-9B-4bit"

    private static let enabledKey = "aiEnabled"

    private(set) var custom: [ModelInfo]
    var selectedId: String {
        didSet { UserDefaults.standard.set(selectedId, forKey: Self.selectedKey) }
    }
    /// U50: the master switch (Settings ▸ AI). Off = no AI menu, no
    /// auto-tag entries in the sidebar; models and the review queue stay.
    var aiEnabled: Bool {
        didSet { UserDefaults.standard.set(aiEnabled, forKey: Self.enabledKey) }
    }
    private(set) var states: [String: State] = [:]
    /// Error of the last "Add model" attempt, shown under the field.
    private(set) var addError: String?
    private(set) var isValidatingCustom = false

    let service = VLMService()

    init() {
        let data = UserDefaults.standard.data(forKey: Self.customKey)
        custom = data.flatMap { try? JSONDecoder().decode([ModelInfo].self, from: $0) } ?? []
        selectedId = UserDefaults.standard.string(forKey: Self.selectedKey) ?? Self.defaultModelId
        aiEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
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
            states[model.id] = Self.restingState(model.id)
        }
    }

    /// The state of a model nobody is downloading right now.
    nonisolated static func restingState(_ id: String) -> State {
        if isInstalled(id) { return .ready }
        let partial = partialBytes(id)
        return partial > 0 ? .partial(partial) : .notDownloaded
    }

    /// Bytes of interrupted downloads waiting in the cache
    /// (`blobs/<etag>.incomplete`, the file huggingface_hub uses too).
    nonisolated static func partialBytes(_ id: String) -> Int64 {
        guard let repo = Repo.ID(rawValue: id) else { return 0 }
        let blobs = HubCache.default.blobsDirectory(repo: repo, kind: .model)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: blobs.path) else { return 0 }
        return names.filter { $0.hasSuffix(".incomplete") }.reduce(0) { sum, name in
            let size = (try? FileManager.default.attributesOfItem(atPath: blobs.appendingPathComponent(name).path)[.size] as? NSNumber)?.int64Value ?? 0
            return sum + size
        }
    }

    /// Installed = a snapshot with config.json AND every weight file the
    /// index names (or at least one safetensors file when there is no
    /// index). The small JSONs arrive first, so a download interrupted by a
    /// quit would otherwise read as "Downloaded" and the next run would
    /// silently pull gigabytes behind a "Loading the model…" bar.
    nonisolated static func isInstalled(_ id: String) -> Bool {
        installedSnapshotDirectory(id) != nil
    }

    nonisolated static func installedSnapshotDirectory(_ id: String) -> URL? {
        guard let repo = Repo.ID(rawValue: id) else { return nil }
        let snapshots = HubCache.default.snapshotsDirectory(repo: repo, kind: .model)
        guard let revisions = try? FileManager.default.contentsOfDirectory(atPath: snapshots.path) else {
            return nil
        }
        let files = FileManager.default
        for revision in revisions {
            let directory = snapshots.appendingPathComponent(revision)
            guard files.fileExists(atPath: directory.appendingPathComponent("config.json").path) else { continue }
            let index = directory.appendingPathComponent("model.safetensors.index.json")
            if let data = try? Data(contentsOf: index),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let weightMap = json["weight_map"] as? [String: String]
            {
                let weights = Set(weightMap.values)
                if weights.allSatisfy({ files.fileExists(atPath: directory.appendingPathComponent($0).path) }) {
                    return directory
                }
            } else if let names = try? files.contentsOfDirectory(atPath: directory.path),
                      names.contains(where: { $0.hasSuffix(".safetensors") })
            {
                return directory
            }
        }
        return nil
    }

    /// The Hugging Face commit the installed snapshot came from — part of the
    /// reply-cache key, because a re-quantised `main` answers differently
    /// under the same repository id.
    nonisolated static func installedRevision(_ id: String) -> String? {
        installedSnapshotDirectory(id)?.lastPathComponent
    }

    /// A note when the model will squeeze this Mac: weights plus activations
    /// plus the app's own caches against the physical memory.
    nonisolated static func memoryNote(for model: ModelInfo) -> String? {
        guard let size = model.sizeGB else { return nil }
        let physicalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1e9
        let needed = size * 1.25 + 4
        guard needed > physicalGB else { return nil }
        return "Tight on this Mac (\(Int(physicalGB.rounded())) GB): expect heavy swapping while it runs."
    }

    // MARK: Download / remove

    private var downloads: [String: Task<Void, Never>] = [:]

    /// Starts (or continues) the download. Files stream into the Hugging
    /// Face cache's own partial-file slot, so Cancel, a lost connection or
    /// a quit lose nothing — the next Download picks up where it stopped.
    func download(_ id: String) {
        if case .downloading = state(of: id) { return }
        guard let repo = Repo.ID(rawValue: id) else {
            states[id] = .failed("“\(id)” is not a valid Hugging Face repository id (expected owner/name).")
            return
        }
        if let size = models.first(where: { $0.id == id })?.sizeGB,
           let free = Self.freeGigabytes()
        {
            let stillNeeded = max(0, size - Double(Self.partialBytes(id)) / 1e9)
            if free < stillNeeded + 1 {
                states[id] = .failed(
                    "Not enough free disk space: the model needs \(stillNeeded.formatted(.number.precision(.fractionLength(1)))) GB more, \(Int(free)) GB are free."
                )
                return
            }
        }
        let size = models.first { $0.id == id }?.sizeGB ?? 0
        states[id] = .downloading(DownloadProgress(bytes: Self.partialBytes(id), total: Int64(size * 1e9)))
        let meter = RateMeter()
        downloads[id] = Task {
            defer { downloads[id] = nil }
            do {
                let downloader = ResumableSnapshotDownloader(
                    repo: repo, revision: "main", patterns: VLMService.downloadPatterns
                )
                try await downloader.run { [weak self] bytes, total in
                    let rate = meter.record(bytes: bytes)
                    Task { @MainActor in
                        guard case .downloading = self?.states[id] else { return }
                        self?.states[id] = .downloading(DownloadProgress(bytes: bytes, total: total, bytesPerSecond: rate))
                    }
                }
                states[id] = Self.isInstalled(id) ? .ready : .failed("The download finished but the weights are incomplete.")
            } catch is CancellationError {
                states[id] = Self.restingState(id)
            } catch {
                states[id] = Self.isInstalled(id) ? .ready : .failed(error.localizedDescription)
            }
        }
    }

    /// Transfer rate from the byte counter: an exponential moving average
    /// over one-second windows, so the number settles instead of flickering
    /// with every packet, yet follows a slowdown within a few seconds.
    private final class RateMeter: @unchecked Sendable {
        private let lock = NSLock()
        private var windowStart: Date?
        private var windowBytes: Int64 = 0
        private var rate: Double?

        func record(bytes: Int64) -> Double? {
            lock.lock(); defer { lock.unlock() }
            let now = Date()
            guard let start = windowStart else {
                windowStart = now
                windowBytes = bytes
                return nil
            }
            let elapsed = now.timeIntervalSince(start)
            guard elapsed >= 1 else { return rate }
            let sample = Double(bytes - windowBytes) / elapsed
            rate = rate.map { $0 * 0.7 + sample * 0.3 } ?? sample
            windowStart = now
            windowBytes = bytes
            return rate
        }
    }

    func cancelDownload(_ id: String) {
        downloads[id]?.cancel()
    }

    nonisolated static func freeGigabytes() -> Double? {
        let values = try? HubCache.default.cacheDirectory.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map { Double($0) / 1e9 }
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
        if selectedId == id { selectedId = Self.defaultModelId }
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
