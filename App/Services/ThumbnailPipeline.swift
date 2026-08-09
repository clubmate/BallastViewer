import BallastCore
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

/// CGImage is immutable and thread-safe; the wrapper carries it across
/// isolation boundaries under strict concurrency.
struct CGImageBox: @unchecked Sendable, Equatable {
    let image: CGImage
    static func == (lhs: CGImageBox, rhs: CGImageBox) -> Bool { lhs.image === rhs.image }
}

/// Decodes and caches thumbnails. The original had no cache at all — this is
/// the single biggest perceived-performance win (spec §16.5).
///
/// - Decodes are *unrotated* (Q5); rotation happens in the view layer, so the
///   cache key excludes orientation and rotating never invalidates anything.
/// - Memory: NSCache bounded at ~300 MB. Disk: JPEG per (path, mtime, bucket)
///   in Caches/Thumbnails/<libraryUUID>/ — regenerable, outside the library.
/// - Decode concurrency is bounded; cancellation is honoured between stages
///   (SwiftUI `.task(id:)` cancels when cells scroll away).
actor ThumbnailPipeline {
    private let cacheDirectory: URL
    /// NSCache is thread-safe; `nonisolated(unsafe)` lets the synchronous
    /// hit paths below read it without an actor hop.
    nonisolated(unsafe) private let memory = NSCache<NSString, CGImage>()
    /// Full-size decodes get their own tiny cache: one 60-MP original costs
    /// ~240 MB — sharing the thumbnail cache would evict every grid thumbnail
    /// after two, three photos in the single view.
    nonisolated(unsafe) private let originalsMemory = NSCache<NSString, CGImage>()
    /// mtime per path, cached for the session: the cache key needs it, and a
    /// per-request `stat` made even 100%-memory-hits pay a syscall (a real
    /// I/O round trip on network volumes). The app itself only rewrites files
    /// in the metadata save — which calls `invalidateModificationTimes()`.
    private let modificationTimes = OSAllocatedUnfairLock<[String: TimeInterval]>(initialState: [:])
    private let counterLock = OSAllocatedUnfairLock<Stats>(initialState: Stats())
    private let maxConcurrentDecodes = 8
    private var activeDecodes = 0
    private var slotWaiters: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

    /// One decode per key, however many cells/views ask for it. Requesters
    /// attach as continuations; the last one to cancel cancels the decode.
    private final class InFlightDecode {
        var continuations: [UUID: CheckedContinuation<CGImageBox?, Never>] = [:]
        var task: Task<Void, Never>?
    }
    private var inFlight: [String: InFlightDecode] = [:]

    struct Stats: Sendable {
        var memoryHits = 0
        var diskHits = 0
        var decodes = 0
    }

    init(libraryUUID: String) {
        // Scale the thumbnail cache with the machine instead of a flat 300 MB:
        // a 768 bitmap costs ~2.3 MB, and holding only two screenfuls made
        // every scroll-back a disk round trip.
        let physical = Int(clamping: ProcessInfo.processInfo.physicalMemory)
        memory.totalCostLimit = min(max(300 * 1024 * 1024, physical / 8), 2 * 1024 * 1024 * 1024)
        originalsMemory.countLimit = 3
        originalsMemory.totalCostLimit = 768 * 1024 * 1024
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches
            .appendingPathComponent("Thumbnails", isDirectory: true)
            .appendingPathComponent(libraryUUID, isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        // The disk cache has no other eviction: stale entries (changed mtime)
        // and closed-forever libraries would grow it without bound. Delayed so
        // the ~100k directory stats don't compete with the first visible
        // thumbnails for disk bandwidth right at library open.
        Task.detached(priority: .utility) { [cacheDirectory] in
            try? await Task.sleep(for: .seconds(30))
            Self.pruneDiskCache(at: cacheDirectory, budgetBytes: 2 * 1024 * 1024 * 1024)
        }
    }

    nonisolated func stats() -> Stats { counterLock.withLock { $0 } }

    /// Wipes the session mtime cache — after the metadata save rewrites files
    /// on disk, their cache keys must re-stat.
    nonisolated func invalidateModificationTimes() {
        modificationTimes.withLock { $0.removeAll() }
    }

    /// Synchronous, hop-free memory lookup. Returns nil when the image is not
    /// in memory OR the path was never stat'ed this session — callers fall
    /// back to the async path then. This is what lets a scrolling grid cell
    /// show a cached thumbnail in the same frame it is configured.
    nonisolated func cachedThumbnail(forPath path: String, longEdge: Int) -> CGImageBox? {
        guard let mtime = modificationTimes.withLock({ $0[path] }) else { return nil }
        let key = "\(path)|\(Int(mtime))|\(longEdge)" as NSString
        guard let hit = memory.object(forKey: key) else { return nil }
        counterLock.withLock { $0.memoryHits += 1 }
        return CGImageBox(image: hit)
    }

    /// Synchronous peek for the single view — same contract as above.
    nonisolated func cachedOriginal(forPath path: String) -> CGImageBox? {
        guard let mtime = modificationTimes.withLock({ $0[path] }) else { return nil }
        let key = "\(path)|\(Int(mtime))|original" as NSString
        guard let hit = originalsMemory.object(forKey: key) else { return nil }
        counterLock.withLock { $0.memoryHits += 1 }
        return CGImageBox(image: hit)
    }

    /// Nonisolated on purpose: the mtime stat is disk I/O — inside the actor it
    /// would serialise every thumbnail request (including pure memory hits)
    /// behind a syscall.
    nonisolated func thumbnail(forPath path: String, longEdge: Int) async -> CGImageBox? {
        let modificationTime = resolvedModificationTime(atPath: path)
        let key = "\(path)|\(Int(modificationTime))|\(longEdge)"
        return await cachedThumbnail(key: key, path: path, longEdge: longEdge)
    }

    /// Full-size decode for the single view (U15): no downscale, no disk cache
    /// (the original is already on disk; a JPEG re-encode would only add loss).
    /// Memory-cached so flipping back and forth between photos stays instant.
    nonisolated func originalImage(forPath path: String) async -> CGImageBox? {
        let modificationTime = resolvedModificationTime(atPath: path)
        let key = "\(path)|\(Int(modificationTime))|original"
        return await cachedOriginal(key: key, path: path)
    }

    /// Session-cached mtime; stats at most once per path per session.
    nonisolated private func resolvedModificationTime(atPath path: String) -> TimeInterval {
        if let cached = modificationTimes.withLock({ $0[path] }) { return cached }
        let fresh = Self.modificationTime(atPath: path)
        modificationTimes.withLock { $0[path] = fresh }
        return fresh
    }

    private func cachedOriginal(key: String, path: String) async -> CGImageBox? {
        if let hit = originalsMemory.object(forKey: key as NSString) {
            counterLock.withLock { $0.memoryHits += 1 }
            return CGImageBox(image: hit)
        }
        return await coalescedDecode(key: key) { [weak self] in
            guard let self else { return nil }
            return await self.performOriginalDecode(key: key, path: path)
        }
    }

    private func performOriginalDecode(key: String, path: String) async -> CGImageBox? {
        do { try await acquireSlot() } catch { return nil }
        defer { releaseSlot() }
        if Task.isCancelled { return nil }
        guard let decoded = await Self.decodeFull(path: path) else { return nil }
        counterLock.withLock { $0.decodes += 1 }
        originalsMemory.setObject(
            decoded.image,
            forKey: key as NSString,
            cost: decoded.image.bytesPerRow * decoded.image.height
        )
        return decoded
    }

    private func cachedThumbnail(key: String, path: String, longEdge: Int) async -> CGImageBox? {
        if let hit = memory.object(forKey: key as NSString) {
            counterLock.withLock { $0.memoryHits += 1 }
            return CGImageBox(image: hit)
        }
        return await coalescedDecode(key: key) { [weak self] in
            guard let self else { return nil }
            return await self.performThumbnailDecode(key: key, path: path, longEdge: longEdge)
        }
    }

    private func performThumbnailDecode(key: String, path: String, longEdge: Int) async -> CGImageBox? {
        do { try await acquireSlot() } catch { return nil }
        defer { releaseSlot() }
        if Task.isCancelled { return nil }

        let cacheFile = cacheDirectory.appendingPathComponent(Self.hash(key) + ".jpg")
        if let cached = await Self.decodeCacheFile(cacheFile) {
            counterLock.withLock { $0.diskHits += 1 }
            store(cached, forKey: key)
            return cached
        }
        if Task.isCancelled { return nil }

        guard let decoded = await Self.decodeOriginal(path: path, longEdge: longEdge) else {
            return nil
        }
        counterLock.withLock { $0.decodes += 1 }
        store(decoded, forKey: key)
        // Off the display path AND off the decode slot: the cell must not
        // wait on JPEG encode + disk write, and the write must not occupy one
        // of the bounded decode slots.
        Task.detached(priority: .utility) {
            await Self.writeCacheFile(decoded, to: cacheFile)
        }
        return decoded
    }

    private func store(_ box: CGImageBox, forKey key: String) {
        memory.setObject(
            box.image,
            forKey: key as NSString,
            cost: box.image.bytesPerRow * box.image.height
        )
    }

    // MARK: In-flight coalescing

    /// Joins an already-running decode for `key` or starts one. Two grid cells
    /// (or cell + single-view prefetch) asking for the same image never decode
    /// twice; a requester that scrolls away detaches, and when the last one
    /// detaches the decode itself is cancelled.
    private func coalescedDecode(
        key: String, _ work: @escaping @Sendable () async -> CGImageBox?
    ) async -> CGImageBox? {
        let requestId = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let entry = inFlight[key] {
                    entry.continuations[requestId] = continuation
                    return
                }
                let entry = InFlightDecode()
                entry.continuations[requestId] = continuation
                inFlight[key] = entry
                entry.task = Task {
                    let value = await work()
                    self.finishDecode(key: key, entry: entry, value: value)
                }
            }
        } onCancel: {
            Task { await self.cancelRequest(key: key, requestId: requestId) }
        }
    }

    private func finishDecode(key: String, entry: InFlightDecode, value: CGImageBox?) {
        if inFlight[key] === entry { inFlight[key] = nil }
        for continuation in entry.continuations.values {
            continuation.resume(returning: value)
        }
        entry.continuations = [:]
    }

    private func cancelRequest(key: String, requestId: UUID) {
        guard let entry = inFlight[key],
              let continuation = entry.continuations.removeValue(forKey: requestId)
        else { return }
        continuation.resume(returning: nil)
        if entry.continuations.isEmpty {
            inFlight[key] = nil
            entry.task?.cancel()
        }
    }

    // MARK: Bounded decode slots

    /// Throws `CancellationError` when the requesting decode is cancelled while
    /// queued — a scrolled-away cell must not keep occupying the FIFO and delay
    /// live requests.
    private func acquireSlot() async throws {
        try Task.checkCancellation()
        if activeDecodes < maxConcurrentDecodes {
            activeDecodes += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                slotWaiters.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelSlotWaiter(id) }
        }
    }

    private func cancelSlotWaiter(_ id: UUID) {
        guard let index = slotWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = slotWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func releaseSlot() {
        if slotWaiters.isEmpty {
            activeDecodes -= 1
        } else {
            slotWaiters.removeFirst().continuation.resume(returning: ())
        }
    }

    // MARK: Decode work (nonisolated async → global executor, off the actor)

    nonisolated private static func decodeOriginal(path: String, longEdge: Int) async -> CGImageBox? {
        let url = URL(fileURLWithPath: path)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
            kCGImageSourceCreateThumbnailWithTransform: false,  // Q5: decode unrotated
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return CGImageBox(image: flattenedIfTransparent(image))
    }

    /// Sources with alpha (transparent PNGs) are flattened onto white at decode
    /// time. The JPEG disk cache cannot store alpha and composites on white
    /// when written — without this, the same photo renders differently
    /// depending on cache tier: composited over the grid background on a fresh
    /// decode, over white after a disk-cache round trip.
    nonisolated private static func flattenedIfTransparent(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return image
        default:
            break
        }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let white = CGColor(colorSpace: space, components: [1, 1, 1, 1]),
              let context = CGContext(
                data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(white)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    nonisolated private static func decodeFull(path: String) async -> CGImageBox? {
        let url = URL(fileURLWithPath: path)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              )
        else { return nil }
        // Q5: CGImageSourceCreateImageAtIndex never applies the EXIF transform —
        // unrotated by construction, matching the grid decode.
        return CGImageBox(image: flattenedIfTransparent(image))
    }

    nonisolated private static func decodeCacheFile(_ url: URL) async -> CGImageBox? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              )
        else { return nil }
        return CGImageBox(image: image)
    }

    /// Plain `stat` — `attributesOfItem` builds the full attribute dictionary
    /// including owner-name lookups, several times the cost.
    nonisolated private static func modificationTime(atPath path: String) -> TimeInterval {
        var status = stat()
        guard stat(path, &status) == 0 else { return 0 }
        return TimeInterval(status.st_mtimespec.tv_sec)
    }

    /// Oldest-first prune to a byte budget. Access times are not tracked
    /// (touching on every hit would cost more than it saves); creation order is
    /// a good-enough proxy for a regenerable cache.
    nonisolated private static func pruneDiskCache(at directory: URL, budgetBytes: Int) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        var files: [(url: URL, size: Int, date: Date)] = entries.compactMap { url in
            guard let values = try? url.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            ) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = files.reduce(0) { $0 + $1.size }
        guard total > budgetBytes else { return }
        files.sort { $0.date < $1.date }
        for file in files {
            guard total > budgetBytes else { break }
            try? fileManager.removeItem(at: file.url)
            total -= file.size
        }
    }

    nonisolated private static func writeCacheFile(_ box: CGImageBox, to url: URL) async {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary
        CGImageDestinationAddImage(destination, box.image, options)
        CGImageDestinationFinalize(destination)
    }

    nonisolated private static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
