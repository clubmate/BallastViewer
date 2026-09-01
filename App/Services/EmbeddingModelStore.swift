import AppKit
import CoreML
import Observation

/// U48: owns the MobileCLIP-S2 CoreML models on disk. The ~200 MB of weights
/// are never bundled (every push builds the release zip) — they download once
/// from Apple's official Hugging Face repo into Application Support, get
/// compiled to `.mlmodelc`, and stay for good. An `.mlpackage` is a directory,
/// so the download fetches each package's `Manifest.json` first and derives
/// the file list from it instead of hardcoding a layout that could drift.
@MainActor @Observable
final class EmbeddingModelStore {
    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case compiling
        case ready
        case failed(String)
    }

    static let modelName = "MobileCLIP-S2"
    /// Cache key component for stored embeddings — bump when the model changes.
    static let modelVersion = "mobileclip-s2-v1"

    private static let repoBase = URL(string: "https://huggingface.co/apple/coreml-mobileclip/resolve/main/")!
    private static let packageNames = ["mobileclip_s2_image.mlpackage", "mobileclip_s2_text.mlpackage"]
    private static let compiledNames = ["ImageEncoder.mlmodelc", "TextEncoder.mlmodelc"]

    private(set) var state: State = .notDownloaded
    private var cachedService: EmbeddingService?

    private let modelsDirectory: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        modelsDirectory = support
            .appendingPathComponent("BallastViewer", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Self.modelName, isDirectory: true)
        if isInstalled { state = .ready }
    }

    var imageModelURL: URL { modelsDirectory.appendingPathComponent(Self.compiledNames[0]) }
    var textModelURL: URL { modelsDirectory.appendingPathComponent(Self.compiledNames[1]) }

    private var isInstalled: Bool {
        FileManager.default.fileExists(atPath: imageModelURL.path)
            && FileManager.default.fileExists(atPath: textModelURL.path)
    }

    /// The shared encoder actor; nil until the models are installed.
    func service() -> EmbeddingService? {
        guard state == .ready else { return nil }
        if let cachedService { return cachedService }
        do {
            let service = try EmbeddingService(imageModelURL: imageModelURL, textModelURL: textModelURL)
            cachedService = service
            return service
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    // MARK: Download

    func download() {
        guard state == .notDownloaded || isFailed else { return }
        state = .downloading(0)
        Task {
            do {
                try await performDownload()
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private struct ModelError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private struct Manifest: Decodable {
        struct Entry: Decodable { let path: String }
        let itemInfoEntries: [String: Entry]
    }

    private func performDownload() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobileclip-download", isDirectory: true)
        try? FileManager.default.removeItem(at: workDir)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // Manifest-first: list every file of both packages, then size them so
        // the progress bar reflects bytes (the weights dwarf everything else).
        var files: [(remote: URL, local: URL)] = []
        for package in Self.packageNames {
            let packageDir = workDir.appendingPathComponent(package, isDirectory: true)
            let manifestRemote = Self.repoBase.appending(path: "\(package)/Manifest.json")
            let manifestLocal = packageDir.appendingPathComponent("Manifest.json")
            try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
            let (data, response) = try await URLSession.shared.data(from: manifestRemote)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw ModelError("The model repository was not reachable (Manifest.json missing).")
            }
            try data.write(to: manifestLocal)
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            for entry in manifest.itemInfoEntries.values {
                // An extension-less LAST component is a DIRECTORY entry —
                // CoreML's weights folder, whose one file is weight.bin
                // (verified against the live repo; the manifest lists only
                // the folder). The full path always contains dots
                // ("com.apple.CoreML/…"), so check the component, not the path.
                let isDirectory = (entry.path as NSString).pathExtension.isEmpty
                let path = isDirectory ? "\(entry.path)/weight.bin" : entry.path
                files.append((
                    remote: Self.repoBase.appending(path: "\(package)/Data/\(path)"),
                    local: packageDir.appendingPathComponent("Data/\(path)")
                ))
            }
        }

        var sizes: [Int64] = []
        for file in files {
            sizes.append(try await Self.remoteSize(of: file.remote))
        }
        let totalBytes = max(1, sizes.reduce(0, +))
        var doneBytes: Int64 = 0

        for (index, file) in files.enumerated() {
            try FileManager.default.createDirectory(
                at: file.local.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let base = doneBytes
            try await Self.download(from: file.remote, to: file.local) { [weak self] written in
                self?.state = .downloading(Double(base + written) / Double(totalBytes))
            }
            doneBytes += sizes[index]
        }

        try await compileAndInstall(
            imagePackage: workDir.appendingPathComponent(Self.packageNames[0]),
            textPackage: workDir.appendingPathComponent(Self.packageNames[1])
        )
    }

    private func compileAndInstall(imagePackage: URL, textPackage: URL) async throws {
        state = .compiling
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        for (package, name) in [(imagePackage, Self.compiledNames[0]), (textPackage, Self.compiledNames[1])] {
            let compiled = try await MLModel.compileModel(at: package)
            let destination = modelsDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: compiled, to: destination)
        }
        cachedService = nil
    }

    /// Escape hatch for when the Hugging Face layout drifts: the user downloads
    /// the two `.mlpackage` folders manually (README documents the repo) and
    /// points the app at the directory containing them.
    func locateManualDownload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Choose the folder containing \(Self.packageNames.joined(separator: " and "))"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        let image = directory.appendingPathComponent(Self.packageNames[0])
        let text = directory.appendingPathComponent(Self.packageNames[1])
        guard FileManager.default.fileExists(atPath: image.path),
              FileManager.default.fileExists(atPath: text.path)
        else {
            state = .failed("The folder does not contain the two MobileCLIP-S2 .mlpackage folders.")
            return
        }
        Task {
            do {
                try await compileAndInstall(imagePackage: image, textPackage: text)
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Transfer

    nonisolated private static func remoteSize(of url: URL) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModelError("A model file was not reachable: \(url.lastPathComponent)")
        }
        return max(0, http.expectedContentLength)
    }

    /// Streams one file to disk, reporting cumulative bytes on the MainActor
    /// (same shape as `AppUpdater.download`).
    nonisolated private static func download(
        from url: URL, to destination: URL,
        progress: @escaping @MainActor (Int64) -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelError("The download failed for \(url.lastPathComponent).")
        }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var written: Int64 = 0
        var lastReported: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if written - lastReported >= 1 << 20 {
                    lastReported = written
                    let snapshot = written
                    await MainActor.run { progress(snapshot) }
                }
            }
        }
        try handle.write(contentsOf: buffer)
    }
}
