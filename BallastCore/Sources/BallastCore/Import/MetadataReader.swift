import Foundation
import ImageIO

public struct PhotoFileMetadata: Equatable, Sendable {
    /// Clamped to 0…5 on read (fixes D5).
    public var rating = 0
    public var orientation = 1
    /// Uppercased, de-duplicated, sorted ascending (spec §6.1).
    public var keywords: [String] = []
    /// EXIF DateTimeOriginal.
    public var captureDate: Date?

    public init(rating: Int = 0, orientation: Int = 1, keywords: [String] = [], captureDate: Date? = nil) {
        self.rating = rating
        self.orientation = orientation
        self.keywords = keywords
        self.captureDate = captureDate
    }
}

/// Reads the three attributes the app cares about, plus capture date.
///
/// Read order fixes D1's read half: XMP (`xmp:Rating`, `dc:subject`) first —
/// that is what Lightroom/Bridge/Capture One write — falling back to IPTC
/// (`StarRating`, `Keywords`). The step-10 writer emits XMP, so round trips hold.
public enum MetadataReader {
    /// An unreadable file yields the defaults — an *empty success*, matching the
    /// original (spec §6.1 [QUIRK]): import keeps defaults instead of failing.
    public static func read(from url: URL) -> PhotoFileMetadata {
        var result = PhotoFileMetadata()
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return result
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions)
            as? [CFString: Any]
        if let orientation = properties?[kCGImagePropertyOrientation] as? Int {
            result.orientation = orientation
        }
        let iptc = properties?[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        if let dateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String {
            result.captureDate = parseEXIFDate(dateString)
        }

        var rating: Int?
        var keywords: [String]?
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            if let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "xmp:Rating" as CFString) {
                rating = intValue(of: tag)
            }
            if let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "dc:subject" as CFString) {
                keywords = stringArray(of: tag)
            }
        }
        if rating == nil {
            rating = iptc?[kCGImagePropertyIPTCStarRating] as? Int
        }
        if keywords == nil {
            if let array = iptc?[kCGImagePropertyIPTCKeywords] as? [String] {
                keywords = array
            } else if let single = iptc?[kCGImagePropertyIPTCKeywords] as? String {
                keywords = [single]
            }
        }

        result.rating = min(5, max(0, rating ?? 0))
        result.keywords = normalizeKeywords(keywords ?? [])
        return result
    }

    /// Uppercase, trim, de-duplicate, sort — the normalisation the whole app's
    /// uppercase-centricity stems from (spec §6.1, Q15).
    public static func normalizeKeywords(_ raw: [String]) -> [String] {
        let cleaned = raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        return Array(Set(cleaned)).sorted()
    }

    // MARK: EXIF date ("2026:07:25 14:30:00", no time zone — local time assumed)

    static func parseEXIFDate(_ string: String) -> Date? {
        let strategy = Date.ParseStrategy(
            format: "\(year: .defaultDigits):\(month: .twoDigits):\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            timeZone: .current
        )
        return try? Date(string, strategy: strategy)
    }

    // MARK: XMP tag values

    private static func intValue(of tag: CGImageMetadataTag) -> Int? {
        let value = CGImageMetadataTagCopyValue(tag)
        if let string = value as? String { return Int(string) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    /// `dc:subject` is a bag: the value is either a single string or an array
    /// whose elements are strings or nested metadata tags.
    private static func stringArray(of tag: CGImageMetadataTag) -> [String] {
        let value = CGImageMetadataTagCopyValue(tag)
        if let string = value as? String { return [string] }
        guard let array = value as? [AnyObject] else { return [] }
        return array.compactMap { element in
            if let string = element as? String { return string }
            if CFGetTypeID(element) == CGImageMetadataTagGetTypeID() {
                return CGImageMetadataTagCopyValue(element as! CGImageMetadataTag) as? String
            }
            return nil
        }
    }
}
