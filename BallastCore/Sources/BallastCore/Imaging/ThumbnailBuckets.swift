/// Thumbnails are decoded into fixed long-edge size buckets so cache entries
/// are reused across small cell-size changes instead of re-decoding per pixel.
public enum ThumbnailBuckets {
    /// Grid-only buckets: the single view decodes the original file directly
    /// (U15), so no display-sized bucket exists.
    public static let all = [256, 768]

    /// Smallest bucket that covers the requested pixel size; the largest
    /// bucket serves everything beyond.
    public static func bucket(forPixelSize size: Int) -> Int {
        all.first { $0 >= size } ?? all[all.count - 1]
    }
}
