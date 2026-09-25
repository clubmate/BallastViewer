import Foundation

extension URL {
    /// Bytes a new file can use on this URL's volume, or nil when the volume
    /// cannot be asked. Prefers the "important usage" figure (APFS counts
    /// purgeable space in it) but falls back to the plain free space: on every
    /// non-APFS volume — exFAT/FAT32 USB sticks, HFS+ — the important-usage
    /// key answers 0, which made Back Up Now refuse a brand-new 128 GB stick
    /// with "Zero KB free".
    var availableBytesForNewFiles: Int64? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? resourceValues(forKeys: keys) else { return nil }
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return values.volumeAvailableCapacity.map { Int64($0) }
    }
}
