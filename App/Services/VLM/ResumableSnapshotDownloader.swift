import Darwin
import Foundation
import HuggingFace

/// U49: downloads a model repository into the standard Hugging Face cache so
/// that an interrupted download continues where it stopped. The library's
/// own `downloadSnapshot` fetches every file through a URLSession download
/// task whose partial file is discarded on cancel, network loss or quit —
/// a 16 GB model starts over each time. This downloader streams each file
/// into the cache's `blobs/<etag>.incomplete` (the very file both
/// huggingface_hub and swift-huggingface resume from), so the next attempt
/// sends a Range request and appends. Files already in the cache are
/// skipped; finished blobs are registered through `HubCache.storeFile`
/// (snapshot symlink + `refs/main`), exactly the layout the runtime's
/// loader reads.
struct ResumableSnapshotDownloader: Sendable {
    let repo: Repo.ID
    let revision: String
    /// fnmatch patterns over repository paths ("*.safetensors").
    let patterns: [String]

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private struct Entry {
        let path: String
        let size: Int64
    }

    private struct FileIdentity {
        let etag: String
        let commit: String
    }

    private static let host = URL(string: "https://huggingface.co")!
    private var cache: HubCache { HubCache.default }

    /// Downloads every matching file; `progress` receives the bytes present
    /// on disk and the total (already-cached files count as done).
    func run(progress: @escaping @Sendable (_ bytes: Int64, _ total: Int64) -> Void) async throws {
        let (listingCommit, entries) = try await listFiles()
        let total = max(entries.reduce(0) { $0 + $1.size }, 1)
        var done: Int64 = 0
        for entry in entries {
            try Task.checkCancellation()
            let base = done
            try await fetch(entry, listingCommit: listingCommit) { bytesOnDisk in
                progress(min(total, base + bytesOnDisk), total)
            }
            done += entry.size
            progress(min(total, done), total)
        }
    }

    // MARK: Listing

    /// The repository's commit and the files matching the patterns, with
    /// their sizes (LFS files carry the real size in `size`).
    private func listFiles() async throws -> (String, [Entry]) {
        let url = Self.host.appending(path: "api/models/\(repo.namespace)/\(repo.name)/revision/\(revision)")
            .appending(queryItems: [URLQueryItem(name: "blobs", value: "true")])
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure("No response from Hugging Face.") }
        guard http.statusCode == 200 else {
            throw Failure(http.statusCode == 404
                ? "No repository “\(repo.rawValue)” on Hugging Face."
                : "Hugging Face answered HTTP \(http.statusCode) for the file list.")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let commit = json["sha"] as? String,
              let siblings = json["siblings"] as? [[String: Any]]
        else { throw Failure("Unexpected file list from Hugging Face.") }
        let entries = siblings.compactMap { sibling -> Entry? in
            guard let path = sibling["rfilename"] as? String, matches(path) else { return nil }
            let size = (sibling["size"] as? NSNumber)?.int64Value
                ?? ((sibling["lfs"] as? [String: Any])?["size"] as? NSNumber)?.int64Value ?? 0
            return Entry(path: path, size: size)
        }
        guard !entries.isEmpty else { throw Failure("The repository has no files matching the model patterns.") }
        return (commit, entries)
    }

    private func matches(_ path: String) -> Bool {
        patterns.contains { fnmatch($0, path, 0) == 0 }
    }

    // MARK: One file

    private func resolveURL(_ path: String) -> URL {
        Self.host.appending(path: "\(repo.namespace)/\(repo.name)/resolve/\(revision)/\(path)")
    }

    /// Etag and commit from a HEAD on the resolve URL. Hugging Face answers
    /// LFS files with a 302 to the CDN; the metadata headers sit on that
    /// redirect, so cross-host redirects are not followed (as the library
    /// does it).
    private func identity(of path: String, fallbackCommit: String) async throws -> FileIdentity {
        var request = URLRequest(url: resolveURL(path))
        request.httpMethod = "HEAD"
        request.timeoutInterval = 30
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (_, response) = try await URLSession.shared.data(for: request, delegate: NoCrossHostRedirect.shared)
        guard let http = response as? HTTPURLResponse else { throw Failure("No response from Hugging Face.") }
        guard (200 ..< 400).contains(http.statusCode) else {
            throw Failure("Hugging Face answered HTTP \(http.statusCode) for \(path).")
        }
        guard let rawEtag = http.value(forHTTPHeaderField: "X-Linked-Etag") ?? http.value(forHTTPHeaderField: "ETag") else {
            throw Failure("Hugging Face sent no ETag for \(path).")
        }
        let commit = http.value(forHTTPHeaderField: "X-Repo-Commit") ?? fallbackCommit
        return FileIdentity(etag: cache.normalizeEtag(rawEtag), commit: commit)
    }

    private func fetch(_ entry: Entry, listingCommit: String, onBytes: @escaping @Sendable (Int64) -> Void) async throws {
        // Already mapped into a snapshot (any revision string resolves via refs).
        if cache.cachedFilePath(repo: repo, kind: .model, revision: revision, filename: entry.path) != nil {
            return
        }
        let identity = try await identity(of: entry.path, fallbackCommit: listingCommit)
        let blob = try cache.blobPath(repo: repo, kind: .model, etag: identity.etag)
        let files = FileManager.default
        if !files.fileExists(atPath: blob.path) {
            let incomplete = try cache.incompleteBlobPath(repo: repo, kind: .model, etag: identity.etag)
            try files.createDirectory(at: incomplete.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await downloadBlob(entry, into: incomplete, onBytes: onBytes)
            if files.fileExists(atPath: blob.path) {
                _ = try files.replaceItemAt(blob, withItemAt: incomplete)
            } else {
                try files.moveItem(at: incomplete, to: blob)
            }
        }
        // Blob present: the snapshot entry (symlink) and refs/main.
        try await cache.storeFile(
            at: blob, repo: repo, kind: .model, revision: identity.commit, filename: entry.path,
            etag: identity.etag, ref: revision == identity.commit ? nil : revision
        )
    }

    /// Streams the file into `incomplete`, appending to whatever is there.
    /// A 416 (the partial file is longer than the server's copy) and a 200
    /// that ignores the Range both start the file over.
    private func downloadBlob(_ entry: Entry, into incomplete: URL, onBytes: @escaping @Sendable (Int64) -> Void) async throws {
        let files = FileManager.default
        for attempt in 0 ..< 2 {
            try Task.checkCancellation()
            if !files.fileExists(atPath: incomplete.path) {
                files.createFile(atPath: incomplete.path, contents: nil)
            }
            let offset = (try? files.attributesOfItem(atPath: incomplete.path)[.size] as? NSNumber)?.int64Value ?? 0
            if entry.size > 0, offset >= entry.size {
                // Everything is there (a previous run stopped between the
                // last byte and the move) — but never trust more than the
                // expected size.
                if offset == entry.size { return }
                try files.removeItem(at: incomplete)
                continue
            }
            var request = URLRequest(url: resolveURL(entry.path))
            request.timeoutInterval = 60
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
            let handle = try FileHandle(forWritingTo: incomplete)
            _ = try handle.seekToEnd()
            let outcome = try await Self.stream(request, to: handle, resumeOffset: offset, onBytes: onBytes)
            switch outcome {
            case .completed:
                if entry.size > 0 {
                    let final = (try? files.attributesOfItem(atPath: incomplete.path)[.size] as? NSNumber)?.int64Value ?? 0
                    guard final == entry.size else {
                        if final > entry.size { try? files.removeItem(at: incomplete) }
                        throw Failure("\(entry.path) arrived incomplete (\(final) of \(entry.size) bytes) — retry to continue.")
                    }
                }
                return
            case .rangeNotSatisfiable:
                try? files.removeItem(at: incomplete)
                guard attempt == 0 else { throw Failure("The server refused to continue \(entry.path).") }
            case .status(let code):
                throw Failure("Hugging Face answered HTTP \(code) for \(entry.path).")
            }
        }
        throw Failure("Could not finish \(entry.path) — retry to continue.")
    }

    private enum Outcome {
        case completed
        case rangeNotSatisfiable
        case status(Int)
    }

    /// A data task writing straight to the file handle. Cancelling the
    /// surrounding task cancels the transfer; the bytes written so far stay.
    private static func stream(
        _ request: URLRequest, to handle: FileHandle, resumeOffset: Int64,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws -> Outcome {
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let delegate = StreamDelegate(handle: handle, resumeOffset: resumeOffset, onBytes: onBytes, continuation: continuation)
                let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
                let task = session.dataTask(with: request)
                box.set(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }

    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDataTask?
        private var cancelled = false

        func set(_ task: URLSessionDataTask) {
            lock.lock(); defer { lock.unlock() }
            self.task = task
            if cancelled { task.cancel() }
        }

        func cancel() {
            lock.lock(); defer { lock.unlock() }
            cancelled = true
            task?.cancel()
        }
    }

    /// Delegate callbacks arrive on the session's serial queue.
    private final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let handle: FileHandle
        private var resumeOffset: Int64
        private let onBytes: @Sendable (Int64) -> Void
        private var continuation: CheckedContinuation<Outcome, Error>?
        private var status: Int?
        private var written: Int64 = 0
        private var writeError: Error?

        init(handle: FileHandle, resumeOffset: Int64, onBytes: @escaping @Sendable (Int64) -> Void,
             continuation: CheckedContinuation<Outcome, Error>) {
            self.handle = handle
            self.resumeOffset = resumeOffset
            self.onBytes = onBytes
            self.continuation = continuation
        }

        func urlSession(
            _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            guard let http = response as? HTTPURLResponse else {
                status = -1
                completionHandler(.cancel)
                return
            }
            status = http.statusCode
            if http.statusCode == 200, resumeOffset > 0 {
                // The server ignored the Range: start the file over.
                do {
                    try handle.truncate(atOffset: 0)
                    resumeOffset = 0
                } catch {
                    writeError = error
                    completionHandler(.cancel)
                    return
                }
            }
            completionHandler((200 ..< 300).contains(http.statusCode) ? .allow : .cancel)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard writeError == nil else { return }
            do {
                try handle.write(contentsOf: data)
                written += Int64(data.count)
                onBytes(resumeOffset + written)
            } catch {
                writeError = error
                dataTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            defer { session.finishTasksAndInvalidate() }
            try? handle.synchronize()
            try? handle.close()
            guard let continuation else { return }
            self.continuation = nil
            if let writeError {
                continuation.resume(throwing: writeError)
            } else if let status, !(200 ..< 300).contains(status) {
                continuation.resume(returning: status == 416 ? .rangeNotSatisfiable : .status(status))
            } else if let error {
                if (error as? URLError)?.code == .cancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error)
                }
            } else {
                continuation.resume(returning: .completed)
            }
        }
    }

    /// Follows same-host redirects only, so the metadata headers of the
    /// 302 to the CDN reach the caller.
    private final class NoCrossHostRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        static let shared = NoCrossHostRedirect()

        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(task.originalRequest?.url?.host == request.url?.host ? request : nil)
        }
    }
}
