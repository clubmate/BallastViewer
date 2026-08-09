/// Thumbnails are decoded into fixed long-edge size buckets so cache entries
/// are reused across small cell-size changes instead of re-decoding per pixel.
public enum ThumbnailBuckets {
    /// Grid-only buckets: the single view decodes the original file directly
    /// (U15), so no display-sized bucket exists. The 512 middle bucket exists
    /// for cache economy: most real column counts fall between 128 and 256 pt
    /// cells, and a 768 bitmap costs ~2.3× the bytes of a 512 one — without
    /// it, the memory cache held barely two screenfuls.
    public static let all = [256, 512, 768]

    /// Smallest bucket that covers the requested pixel size; the largest
    /// bucket serves everything beyond.
    public static func bucket(forPixelSize size: Int) -> Int {
        all.first { $0 >= size } ?? all[all.count - 1]
    }
}
