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
/// and only the rating/keyword tags are patched in merge mode, preserving all
/// other metadata. Writes go to a temp file first, then atomically replace the
/// original; a failure leaves the original untouched.
///
/// The format is Lightroom's (so Lightroom/Bridge/Capture One read the
/// hierarchy back verbatim):
/// - `xmp:Rating`
/// - `dc:subject` — flat bag of EVERY path component, de-duplicated
///   (Lightroom's "include parent keywords on export" style)
/// - `lr:hierarchicalSubject` — one entry per keyword path, components joined
///   with `|` (namespace `http://ns.adobe.com/lightroom/1.0/`)
///
/// An empty keyword set writes EMPTY arrays rather than deleting the tags:
/// readers that fall back to IPTC `Keywords` when `dc:subject` is absent
/// would otherwise resurrect stale keywords from the IPTC block.
///
/// `write` is the automatic write-through (`MetadataWriteThrough` in the app:
/// every keyword/rating change lands in the file seconds later);
/// `writeOrientation` is the BallastPicker's rotation. No other code writes
/// image files.
///
/// PIXEL INVARIANT (CLAUDE.md): this is one of only two places that write an
/// image file. Every change here must keep `PixelInvariantTests` green — it
/// compares the compressed image data byte-for-byte before and after a write.
public enum MetadataWriter {
    public static let lightroomNamespace = "http://ns.adobe.com/lightroom/1.0/"
    public static let lightroomPrefix = "lr"
    /// Lightroom's path separator inside `lr:hierarchicalSubject`.
    public static let hierarchySeparator = "|"

    /// `keywordPaths`: one component array per keyword path, already
    /// UPPERCASE (the storage invariant); `["PEOPLE", "ANNA"]` becomes
    /// `PEOPLE|ANNA`. Order is not significant; the writer sorts.
    public static func write(
        rating: Int,
        keywordPaths: [[String]],
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
        let cleanPaths = keywordPaths
            .map { $0.map(KeywordDAO.normalize).filter { !$0.isEmpty } }
            .filter { !$0.isEmpty }
        let flat = Array(Set(cleanPaths.flatMap { $0 })).sorted()
        let hierarchical = Array(Set(cleanPaths.map { $0.joined(separator: hierarchySeparator) }))
            .sorted()

        var registerError: Unmanaged<CFError>?
        guard
            CGImageMetadataRegisterNamespaceForPrefix(
                patch, lightroomNamespace as CFString, lightroomPrefix as CFString, &registerError
            ),
            CGImageMetadataSetValueWithPath(
                patch, nil, "xmp:Rating" as CFString, String(rating) as CFTypeRef
            ),
            CGImageMetadataSetValueWithPath(patch, nil, "dc:subject" as CFString, flat as CFTypeRef),
            // Emits an rdf:Seq where Lightroom itself writes an rdf:Bag; the
            // XMP toolkit reads either. (A Bag built with
            // CGImageMetadataTagCreate makes ImageIO drop the WHOLE patch on
            // PNG — silently, rating included — so the plain path setter it is.)
            CGImageMetadataSetValueWithPath(
                patch, nil, "\(lightroomPrefix):hierarchicalSubject" as CFString,
                hierarchical as CFTypeRef
            )
        else {
            throw MetadataWriteError.writeFailed("Could not build the metadata patch.")
        }

        try copyPatched(source: source, type: type, patch: patch, extraOptions: [:], to: url)
    }

    /// ImageIO writes no XMP at all into a PNG that carries no metadata chunk
    /// yet (the merge has nothing to merge into, and the patch is dropped
    /// silently — rating included). The copy is byte-verbatim otherwise, so
    /// the packet is spliced in as an `iTXt` chunk ahead of the first IDAT —
    /// the standard PNG XMP carrier ImageIO itself reads back. IDAT bytes are
    /// never touched.
    private static func ensurePNGCarriesPatch(
        _ patch: CGMutableImageMetadata, tempURL: URL, type: CFString
    ) throws {
        guard type == "public.png" as CFString else { return }
        if let written = CGImageSourceCreateWithURL(tempURL as CFURL, nil),
           let metadata = CGImageSourceCopyMetadataAtIndex(written, 0, nil),
           CGImageMetadataCopyTagWithPath(metadata, nil, "xmp:Rating" as CFString) != nil {
            return
        }
        guard let packet = CGImageMetadataCreateXMPData(patch, nil) as Data? else {
            throw MetadataWriteError.writeFailed("Could not serialise the XMP packet.")
        }
        var bytes = try Data(contentsOf: tempURL)
        guard let insertAt = PNGChunks.firstIDATOffset(in: bytes) else {
            throw MetadataWriteError.writeFailed("Not a valid PNG.")
        }
        bytes.insert(contentsOf: PNGChunks.xmpChunk(packet), at: insertAt)
        try bytes.write(to: tempURL)
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
        if let patch {
            try ensurePNGCarriesPatch(patch, tempURL: tempURL, type: type)
        }

        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }
}

/// Minimal PNG chunk plumbing for the XMP `iTXt` splice. Nothing here reads
/// or writes image data: it only walks chunk headers.
enum PNGChunks {
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Byte offset of the first IDAT chunk's length field, or nil when the
    /// data is not a PNG.
    static func firstIDATOffset(in data: Data) -> Int? {
        guard data.count > 8, Array(data.prefix(8)) == signature else { return nil }
        var offset = 8
        while offset + 8 <= data.count {
            let length = Int(data[offset]) << 24 | Int(data[offset + 1]) << 16
                | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            if type == "IDAT" || type == "IEND" { return offset }
            offset += 12 + length
        }
        return nil
    }

    /// An `iTXt` chunk with keyword `XML:com.adobe.xmp`, uncompressed.
    static func xmpChunk(_ packet: Data) -> Data {
        var body = Data("XML:com.adobe.xmp".utf8)
        body.append(contentsOf: [0, 0, 0, 0, 0]) // NUL, compression flag, method, lang NUL, translated NUL
        body.append(packet)
        var chunk = Data()
        var length = UInt32(body.count).bigEndian
        chunk.append(Data(bytes: &length, count: 4))
        var typed = Data("iTXt".utf8)
        typed.append(body)
        chunk.append(typed)
        var crc = crc32(typed).bigEndian
        chunk.append(Data(bytes: &crc, count: 4))
        return chunk
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}

/// The change test of the write-through: a file whose rating and keyword
/// path SET already match the library is not rewritten. Orientation is
/// library-only (Q5) and capture date is read-only — neither takes part.
public enum MetadataSync {
    public static func differs(_ a: PhotoFileMetadata, _ b: PhotoFileMetadata) -> Bool {
        a.rating != b.rating || Set(a.keywords) != Set(b.keywords)
    }
}
