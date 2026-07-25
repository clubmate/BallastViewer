import BallastCore
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
    private let memory = NSCache<NSString, CGImage>()
    private let maxConcurrentDecodes = 8
    private var activeDecodes = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    struct Stats: Sendable {
        var memoryHits = 0
        var diskHits = 0
        var decodes = 0
    }
    private var counters = Stats()

    init(libraryUUID: String) {
        memory.totalCostLimit = 300 * 1024 * 1024
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches
            .appendingPathComponent("Thumbnails", isDirectory: true)
            .appendingPathComponent(libraryUUID, isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func stats() -> Stats { counters }

    func thumbnail(forPath path: String, longEdge: Int) async -> CGImageBox? {
        let modificationTime = (try? FileManager.default
            .attributesOfItem(atPath: path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let key = "\(path)|\(Int(modificationTime))|\(longEdge)"
        if let hit = memory.object(forKey: key as NSString) {
            counters.memoryHits += 1
            return CGImageBox(image: hit)
        }

        await acquireSlot()
        defer { releaseSlot() }
        if Task.isCancelled { return nil }

        let cacheFile = cacheDirectory.appendingPathComponent(Self.hash(key) + ".jpg")
        if let cached = await Self.decodeCacheFile(cacheFile) {
            counters.diskHits += 1
            store(cached, forKey: key)
            return cached
        }
        if Task.isCancelled { return nil }

        guard let decoded = await Self.decodeOriginal(path: path, longEdge: longEdge) else {
            return nil
        }
        counters.decodes += 1
        store(decoded, forKey: key)
        await Self.writeCacheFile(decoded, to: cacheFile)
        return decoded
    }

    private func store(_ box: CGImageBox, forKey key: String) {
        memory.setObject(
            box.image,
            forKey: key as NSString,
            cost: box.image.bytesPerRow * box.image.height
        )
    }

    // MARK: Bounded decode slots

    private func acquireSlot() async {
        if activeDecodes < maxConcurrentDecodes {
            activeDecodes += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func releaseSlot() {
        if waiters.isEmpty {
            activeDecodes -= 1
        } else {
            waiters.removeFirst().resume()
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
        return CGImageBox(image: image)
    }

    nonisolated private static func decodeCacheFile(_ url: URL) async -> CGImageBox? {
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              )
        else { return nil }
        return CGImageBox(image: image)
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
