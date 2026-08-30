import BallastCore
import Foundation
import Observation
import os

/// Automatic, Lightroom-compatible metadata write-through: every rating or
/// keyword change lands in the image file by itself — no Save command.
///
/// Flow per photo:
/// 1. A mutation marks the photo dirty (`needsFileWrite`, memory + DB — the
///    flag survives a crash) and calls `schedule`.
/// 2. Debounce: 2 s of quiet per photo, so a burst of rating presses costs
///    one file write. Moving the selection off a photo flushes it at once
///    (`flush`), so culling forward never leaves the previous photo pending.
/// 3. A single serial writer (one file at a time, off the MainActor) reads
///    the photo's CURRENT library values, skips the write when the file
///    already agrees, otherwise patches the file — `MetadataWriter.write`,
///    pixels untouched by construction — and clears the flag on success.
///    A failure keeps the flag, logs, and counts; the next open retries.
/// 4. After a rewrite the file's mtime changed, so the thumbnail cache is
///    re-keyed (`ThumbnailPipeline.fileRewritten`) instead of re-decoded.
///
/// A generation counter per photo keeps a write that raced a newer mutation
/// from clearing the flag: the flag is cleared only if nothing changed since
/// the write captured its values.
@MainActor @Observable
final class MetadataWriteThrough {
    @ObservationIgnored private unowned let controller: LibraryController
    @ObservationIgnored private let logger = Logger(subsystem: "com.bolliboll.ballastviewer", category: "WriteThrough")

    /// Debounce tasks per photo id.
    @ObservationIgnored private var debounces: [Int64: Task<Void, Never>] = [:]
    /// Bumped on every mark; a completed write only clears the dirty flag if
    /// the generation it captured is still current.
    @ObservationIgnored private var generation: [Int64: UInt64] = [:]
    /// Serial writer queue (FIFO, de-duplicated) and the drain driving it.
    @ObservationIgnored private var queue: [Int64] = []
    @ObservationIgnored private var queued: Set<Int64> = []
    @ObservationIgnored private var drain: Task<Void, Never>?
    @ObservationIgnored private var isShutDown = false

    /// Files whose last write failed (still dirty; retried on next open or
    /// next change). Observable so a status view can show a count if wanted.
    private(set) var failedPaths: Set<String> = []
    /// Photos waiting or in flight — for an optional status indicator.
    private(set) var pendingCount = 0
    /// Photos in the current write burst (grows while new work arrives, resets
    /// to 0 when the queue drains) — the "of M" for a progress bar.
    private(set) var runTotal = 0
    /// The "N" for a progress bar: photos of the current burst already handled.
    var completedCount: Int { max(0, runTotal - pendingCount) }
    /// The photo currently being written — counted as pending until its
    /// outcome lands, so the bar never claims completion early.
    @ObservationIgnored private var inFlightCount = 0

    static let debounceInterval: Duration = .seconds(2)

    init(controller: LibraryController) {
        self.controller = controller
    }

    // MARK: Entry points (MainActor)

    /// Photos whose rating/keywords just changed: (re)start their debounce.
    func schedule(_ ids: [Int64]) {
        guard !isShutDown else { return }
        for id in ids {
            generation[id, default: 0] &+= 1
            debounces[id]?.cancel()
            debounces[id] = Task { [weak self] in
                try? await Task.sleep(for: Self.debounceInterval)
                guard !Task.isCancelled, let self else { return }
                self.debounces[id] = nil
                self.enqueue(id)
            }
        }
        updatePendingCount()
    }

    /// The selection moved off this photo: write it now instead of in 2 s.
    func flush(_ id: Int64) {
        guard let task = debounces.removeValue(forKey: id) else { return }
        task.cancel()
        enqueue(id)
    }

    /// Library open: everything still flagged from an earlier session.
    func enqueueAll(_ ids: [Int64]) {
        for id in ids { enqueue(id) }
    }

    /// Termination: fold every debounce into the queue and wait for the
    /// writer, capped so a stuck volume cannot hold ⌘Q hostage. Whatever is
    /// left stays flagged for the next open.
    func drainForTermination(timeout: Duration = .seconds(8)) async {
        for (id, task) in debounces {
            task.cancel()
            enqueue(id)
        }
        debounces = [:]
        isShutDown = true
        guard let drain else { return }
        let finished = await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask { await drain.value; return true }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            // Cancels only the waiters — the drain itself keeps going until
            // the process exits, and the flags cover whatever it misses.
            group.cancelAll()
            return first
        }
        if !finished {
            logger.warning("Termination hit the write-through timeout; \(self.queue.count) file(s) stay flagged.")
        }
    }

    /// Library closing: stop scheduling; in-flight work is abandoned (the
    /// dirty flags in the closed library keep the work for next time).
    func shutdown() {
        isShutDown = true
        for task in debounces.values { task.cancel() }
        debounces = [:]
        drain?.cancel()
    }

    // MARK: Queue

    private func enqueue(_ id: Int64) {
        guard queued.insert(id).inserted else { return }
        queue.append(id)
        updatePendingCount()
        if drain == nil {
            drain = Task { [weak self] in
                await self?.runDrain()
                self?.drain = nil
            }
        }
    }

    private func updatePendingCount() {
        let count = debounces.count + queue.count + inFlightCount
        if count > pendingCount { runTotal += count - pendingCount }
        if count == 0 { runTotal = 0 }
        if count != pendingCount { pendingCount = count }
    }

    private struct Job: Sendable {
        var id: Int64
        var path: String
        var generation: UInt64
        var values: PhotoFileMetadata
        var keywordPaths: [[String]]
    }

    private enum Outcome: Sendable {
        case written
        case inSync
        case failed(String)
    }

    /// The serial writer: one file at a time, values read on the MainActor
    /// right before each write, the I/O detached.
    private func runDrain() async {
        while !queue.isEmpty, !Task.isCancelled {
            let id = queue.removeFirst()
            queued.remove(id)
            inFlightCount = 1
            defer {
                inFlightCount = 0
                updatePendingCount()
            }
            updatePendingCount()
            guard let job = makeJob(for: id) else {
                // Photo left the catalog (folder removed) — nothing to write.
                continue
            }
            let outcome = await Task.detached(priority: .utility) { Self.perform(job) }.value
            guard !Task.isCancelled else { return }
            switch outcome {
            case .written, .inSync:
                failedPaths.remove(job.path)
                if (generation[id] ?? 0) == job.generation {
                    controller.clearNeedsFileWrite([id])
                    generation[id] = nil
                }
                if case .written = outcome {
                    await controller.thumbnails?.fileRewritten(paths: [job.path])
                }
            case .failed(let reason):
                failedPaths.insert(job.path)
                logger.error("Metadata write failed for \(job.path, privacy: .public): \(reason, privacy: .public)")
            }
        }
    }

    private func makeJob(for id: Int64) -> Job? {
        guard let photo = controller.photo(withId: id), let snapshot = controller.snapshot else { return nil }
        let keywordIds = snapshot.keywordIdsByPhoto[id] ?? []
        let paths = keywordIds.map { snapshot.keywordTree.pathComponents(of: $0) }.filter { !$0.isEmpty }
        return Job(
            id: id,
            path: photo.path,
            generation: generation[id] ?? 0,
            values: PhotoFileMetadata(
                rating: photo.rating,
                keywords: MetadataReader.normalizeKeywordPaths(paths)
            ),
            keywordPaths: paths
        )
    }

    /// Off the MainActor. Read → compare → write; an unreadable file is a
    /// failure (reported, flag kept) — never written blind.
    nonisolated private static func perform(_ job: Job) -> Outcome {
        let url = URL(fileURLWithPath: job.path)
        guard let fileValues = MetadataReader.readIfReadable(from: url) else {
            return .failed("unreadable or missing")
        }
        guard MetadataSync.differs(job.values, fileValues) else { return .inSync }
        do {
            try MetadataWriter.write(rating: job.values.rating, keywordPaths: job.keywordPaths, to: url)
            return .written
        } catch {
            return .failed(String(describing: error))
        }
    }
}
