import Foundation
import ImageIO

public enum MetadataWriteError: Error {
    /// The source could not be opened or is not an image (Q27: callers report
    /// these files instead of silently skipping them).
    case unreadableSource(String)
    case writeFailed(String)
}

/// Lossless metadata write-back (spec §6.2): the image data is copied
/// byte-for-byte via `CGImageDestinationCopyImageSource` — never recompressed —
/// and only three tags are patched in merge mode, preserving all other
/// metadata. Writes go to a temp file first, then atomically replace the
/// original; a failure leaves the original untouched.
///
/// The writer emits XMP (`tiff:Orientation`, `xmp:Rating`, `dc:subject`) —
/// the industry schema (Lightroom/Bridge/Capture One). Together with the
/// XMP-first reader this closes D1: values round-trip by construction.
///
/// PIXEL INVARIANT (CLAUDE.md): this is one of only two places that write an
/// image file. Every change here must keep `PixelInvariantTests` green — it
/// compares the compressed image data byte-for-byte before and after a write.
public enum MetadataWriter {
    public static func write(
        rating: Int,
        orientation: Int,
        keywords: [String],
        to url: URL
    ) throws {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source)
        else {
            throw MetadataWriteError.unreadableSource(url.path)
        }

        let patch = CGImageMetadataCreateMutable()
        // An empty keyword list must *clear* dc:subject — kCFNull in the merge
        // patch deletes the tag (leaving it stale would resurrect old keywords
        // on the next Load).
        let subjectValue: CFTypeRef = keywords.isEmpty ? kCFNull : keywords as CFTypeRef
        guard
            CGImageMetadataSetValueWithPath(
                patch, nil, "tiff:Orientation" as CFString, String(orientation) as CFTypeRef
            ),
            CGImageMetadataSetValueWithPath(
                patch, nil, "xmp:Rating" as CFString, String(rating) as CFTypeRef
            ),
            CGImageMetadataSetValueWithPath(patch, nil, "dc:subject" as CFString, subjectValue)
        else {
            throw MetadataWriteError.writeFailed("Could not build the metadata patch.")
        }

        try copyPatched(source: source, type: type, patch: patch, extraOptions: [:], to: url)
    }

    /// Orientation-only variant for the Photo Picker utility: patches XMP
    /// `tiff:Orientation` AND the classic EXIF/TIFF orientation tag (via
    /// `kCGImageDestinationOrientation`), so Finder, Preview and Lightroom all
    /// agree. Rating and keywords are left exactly as they are — the picker
    /// works on files that are not part of any library.
    public static func writeOrientation(_ orientation: Int, to url: URL) throws {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source)
        else {
            throw MetadataWriteError.unreadableSource(url.path)
        }
        // ImageIO refuses kCGImageDestinationMetadata together with
        // kCGImageDestinationOrientation, so the EXIF/TIFF tag goes in via
        // the dedicated option alone (ImageIO keeps XMP in step itself).
        try copyPatched(
            source: source, type: type, patch: nil,
            extraOptions: [kCGImageDestinationOrientation: orientation],
            to: url
        )
    }

    /// Shared lossless copy: temp file on the same volume as the original so
    /// the final replace stays atomic (spec §6.2 steps 2/5).
    private static func copyPatched(
        source: CGImageSource,
        type: CFString,
        patch: CGMutableImageMetadata?,
        extraOptions: [CFString: Any],
        to url: URL
    ) throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: url, create: true
        )
        // The replacement directory is ours to clean up — `replaceItemAt` only
        // consumes the file inside it; without this every save leaks an empty
        // "(A Document Being Saved By …)" directory.
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let tempURL = tempDir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)

        guard let destination = CGImageDestinationCreateWithURL(
            tempURL as CFURL, type, CGImageSourceGetCount(source), nil
        ) else {
            throw MetadataWriteError.writeFailed("Could not create the destination file.")
        }

        var options: [CFString: Any] = [:]
        if let patch {
            options[kCGImageDestinationMetadata] = patch
            options[kCGImageDestinationMergeMetadata] = true
        }
        options.merge(extraOptions) { _, new in new }
        var copyError: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(
            destination, source, options as CFDictionary, &copyError
        ) else {
            let reason = (copyError?.takeRetainedValue()).map(String.init(describing:))
                ?? "unknown error"
            throw MetadataWriteError.writeFailed(reason)
        }

        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }
}

/// The shared change test of the two sync commands (spec §6.4): compares the
/// three synced attributes, keywords as a *set* in both directions (the
/// original compared sets on Save but ordered arrays on Load). Capture date is
/// read-only and never part of the comparison.
public enum MetadataSync {
    public static func differs(_ a: PhotoFileMetadata, _ b: PhotoFileMetadata) -> Bool {
        a.rating != b.rating
            || a.orientation != b.orientation
            || Set(a.keywords) != Set(b.keywords)
    }
}
