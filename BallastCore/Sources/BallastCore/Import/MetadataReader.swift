import Foundation
import ImageIO

public struct PhotoFileMetadata: Equatable, Sendable {
    /// Clamped to 0…5 on read (fixes D5).
    public var rating = 0
    public var orientation = 1
    /// Keyword PATHS in the app's canonical form — components joined with
    /// `KeywordTree.separator` (`"PEOPLE > ANNA"`) — uppercased,
    /// de-duplicated, sorted ascending (spec §6.1). Parsed from Lightroom's
    /// `lr:hierarchicalSubject` (`PEOPLE|ANNA`) when present.
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
/// Keywords (Lightroom-compatible, fixes D1's read half):
/// 1. `lr:hierarchicalSubject` — one path per entry, `|`-separated;
/// 2. otherwise `dc:subject`, where each entry may itself be a path using
///    `|` (Lightroom), `" > "` (this app's legacy writer) or be flat;
/// 3. IPTC `Keywords` ONLY when the file has no XMP packet at all — a packet
///    with an empty `dc:subject` means "no keywords", and the stale IPTC
///    block ImageIO keeps in step must not resurrect them.
/// Rating: `xmp:Rating`, falling back to IPTC `StarRating`.
public enum MetadataReader {
    /// An unreadable file yields the defaults — an *empty success*, matching the
    /// original (spec §6.1 [QUIRK]): import keeps defaults instead of failing.
    public static func read(from url: URL) -> PhotoFileMetadata {
        readIfReadable(from: url) ?? PhotoFileMetadata()
    }

    /// Like `read(from:)` but distinguishes "unreadable" (nil) from "readable
    /// with no metadata". The sync commands must skip unreadable files instead
    /// of treating them as empty — otherwise Load wipes library data (spec §6.1
    /// quirk, Q27 makes the skipped files visible).
    public static func readIfReadable(from url: URL) -> PhotoFileMetadata? {
        var result = PhotoFileMetadata()
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              CGImageSourceGetCount(source) > 0
        else {
            return nil
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions)
            as? [CFString: Any]
        // Only EXIF 1…8 are meaningful; anything else (0, 9+) would be stored
        // verbatim and written back into the file's XMP on Save. Mirror the
        // rating clamp (D5): out of range reads as "normal".
        if let orientation = properties?[kCGImagePropertyOrientation] as? Int {
            result.orientation = (1...8).contains(orientation) ? orientation : 1
        }
        let iptc = properties?[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        if let dateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String {
            result.captureDate = parseEXIFDate(dateString)
        }

        var rating: Int?
        var keywordPaths: [[String]]?
        var hasXMP = false
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            hasXMP = true
            if let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "xmp:Rating" as CFString) {
                rating = intValue(of: tag)
            }
            let hierarchicalPath = "\(MetadataWriter.lightroomPrefix):hierarchicalSubject" as CFString
            if let tag = CGImageMetadataCopyTagWithPath(metadata, nil, hierarchicalPath) {
                keywordPaths = stringArray(of: tag).map(Self.parsePath)
            } else if let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "dc:subject" as CFString) {
                keywordPaths = stringArray(of: tag).map(Self.parsePath)
            }
        }
        if rating == nil {
            rating = iptc?[kCGImagePropertyIPTCStarRating] as? Int
        }
        if keywordPaths == nil, !hasXMP {
            if let array = iptc?[kCGImagePropertyIPTCKeywords] as? [String] {
                keywordPaths = array.map(Self.parsePath)
            } else if let single = iptc?[kCGImagePropertyIPTCKeywords] as? String {
                keywordPaths = [Self.parsePath(single)]
            }
        }

        result.rating = min(5, max(0, rating ?? 0))
        result.keywords = normalizeKeywordPaths(keywordPaths ?? [])
        return result
    }

    /// Splits one file entry into path components: `|` (Lightroom) wins,
    /// then the legacy `" > "`; a flat entry is a single component. Components
    /// are normalised individually so `"people|anna"` and `"PEOPLE > ANNA"`
    /// both become `["PEOPLE", "ANNA"]`.
    public static func parsePath(_ entry: String) -> [String] {
        let pieces: [String]
        if entry.contains(MetadataWriter.hierarchySeparator) {
            pieces = entry.components(separatedBy: MetadataWriter.hierarchySeparator)
        } else if entry.contains(KeywordTree.separator) {
            pieces = entry.components(separatedBy: KeywordTree.separator)
        } else {
            // Tolerate `PEOPLE>ANNA` / `PEOPLE >ANNA` from hand-edited files.
            pieces = entry.components(separatedBy: ">")
        }
        return pieces.map(KeywordDAO.normalize).filter { !$0.isEmpty }
    }

    /// Canonical path strings from component arrays: joined with
    /// `KeywordTree.separator`, de-duplicated, sorted.
    public static func normalizeKeywordPaths(_ paths: [[String]]) -> [String] {
        let joined = paths
            .map { $0.map(KeywordDAO.normalize).filter { !$0.isEmpty } }
            .filter { !$0.isEmpty }
            .map { $0.joined(separator: KeywordTree.separator) }
        return Array(Set(joined)).sorted()
    }

    /// Uppercase, trim, NFC, de-duplicate, sort — the normalisation the whole
    /// app's uppercase-centricity stems from (spec §6.1, Q15). Delegates the
    /// per-string rule to `KeywordDAO.normalize` so files and typed input agree
    /// byte-for-byte (decomposed umlauts from XMP would otherwise duplicate).
    public static func normalizeKeywords(_ raw: [String]) -> [String] {
        let cleaned = raw
            .map { KeywordDAO.normalize($0) }
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
