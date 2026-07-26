/// Thumbnails are decoded into fixed long-edge size buckets so cache entries
/// are reused across small cell-size changes instead of re-decoding per pixel.
public enum ThumbnailBuckets {
    public static let all = [256, 768, 2048]

    /// The single-view display bucket.
    public static var largest: Int { all[all.count - 1] }

    /// Smallest bucket that covers the requested pixel size; the largest
    /// bucket serves everything beyond.
    public static func bucket(forPixelSize size: Int) -> Int {
        all.first { $0 >= size } ?? all[all.count - 1]
    }
}
