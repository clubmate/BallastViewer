import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import BallastCore

/// Renders an image file to raw RGBA bytes — the "pixels identical" acceptance
/// check compares these, since a metadata rewrite legitimately changes the
/// container bytes but must never touch the image data.
private func pixelBytes(of url: URL) throws -> Data {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw MetadataWriteError.unreadableSource(url.path) }
    let width = image.width
    let height = image.height
    var data = Data(count: width * height * 4)
    data.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return data
}

struct MetadataWriterTests {
    private func tempJPEG(named name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name).jpg")
    }

    @Test func writeReadRoundTripAndMergePreservesEXIF() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJPEG(to: url, properties: [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2024:06:01 10:30:00"
            ] as [CFString: Any],
        ])

        try MetadataWriter.write(
            rating: 4, orientation: 6, keywords: ["PEOPLE > ANNA", "TRIP"], to: url
        )

        // D1 acceptance: the XMP-first reader returns exactly what was written.
        let metadata = MetadataReader.read(from: url)
        #expect(metadata.rating == 4)
        #expect(metadata.orientation == 6)
        #expect(metadata.keywords == ["PEOPLE > ANNA", "TRIP"])
        // Merge mode: untouched metadata (EXIF capture date) survives.
        #expect(metadata.captureDate != nil)
    }

    @Test func orientationOnlyWriteSetsEXIFAndXMPAndKeepsRatingKeywords() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJPEG(to: url, properties: [:])
        try MetadataWriter.write(rating: 2, orientation: 1, keywords: ["KEEP"], to: url)
        let before = try pixelBytes(of: url)

        try MetadataWriter.writeOrientation(8, to: url)

        let metadata = MetadataReader.read(from: url)
        #expect(metadata.orientation == 8)
        #expect(metadata.rating == 2)
        #expect(metadata.keywords == ["KEEP"])
        #expect(try pixelBytes(of: url) == before)
        // The classic EXIF/TIFF tag (what Finder/Preview read) is set too.
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect(props?[kCGImagePropertyOrientation] as? Int == 8)
        let tiff = props?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFOrientation] as? Int == 8)
        let xmp = try #require(CGImageSourceCopyMetadataAtIndex(source, 0, nil))
        let tag = CGImageMetadataCopyTagWithPath(xmp, nil, "tiff:Orientation" as CFString)
        #expect(tag.flatMap { CGImageMetadataTagCopyValue($0) as? String } == "8")
    }

    @Test func imagePixelsAreUntouched() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJPEG(to: url, properties: [:])
        let before = try pixelBytes(of: url)

        try MetadataWriter.write(rating: 5, orientation: 8, keywords: ["X"], to: url)

        #expect(try pixelBytes(of: url) == before)
    }

    @Test func secondWriteUpdatesAndEmptyKeywordsClear() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJPEG(to: url, properties: [:])

        try MetadataWriter.write(rating: 3, orientation: 1, keywords: ["OLD", "STALE"], to: url)
        try MetadataWriter.write(rating: 0, orientation: 3, keywords: [], to: url)

        let metadata = MetadataReader.read(from: url)
        #expect(metadata.rating == 0)
        #expect(metadata.orientation == 3)
        // Stale keywords must not survive an empty write (kCFNull deletion).
        #expect(metadata.keywords.isEmpty)
    }

    @Test func unreadableSourceThrowsAndLeavesFileAlone() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-an-image.txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let content = Data("plain text".utf8)
        try content.write(to: url)

        #expect(throws: MetadataWriteError.self) {
            try MetadataWriter.write(rating: 1, orientation: 1, keywords: [], to: url)
        }
        #expect(try Data(contentsOf: url) == content)
        #expect(MetadataReader.readIfReadable(from: url) == nil)
    }

    @Test func readIfReadableDistinguishesEmptyFromUnreadable() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJPEG(to: url, properties: [:])
        // Readable but bare: non-nil with defaults.
        #expect(MetadataReader.readIfReadable(from: url) == PhotoFileMetadata(orientation: 1))
        // Missing file: nil, not an empty success.
        #expect(MetadataReader.readIfReadable(from: url.appendingPathExtension("gone")) == nil)
    }
}

struct MetadataSyncTests {
    @Test func comparesKeywordsAsSet() {
        let a = PhotoFileMetadata(rating: 3, orientation: 1, keywords: ["A", "B"])
        let b = PhotoFileMetadata(rating: 3, orientation: 1, keywords: ["B", "A"])
        #expect(!MetadataSync.differs(a, b))
    }

    @Test func detectsEachAttribute() {
        let base = PhotoFileMetadata(rating: 3, orientation: 1, keywords: ["A"])
        #expect(MetadataSync.differs(base, PhotoFileMetadata(rating: 4, orientation: 1, keywords: ["A"])))
        #expect(MetadataSync.differs(base, PhotoFileMetadata(rating: 3, orientation: 6, keywords: ["A"])))
        #expect(MetadataSync.differs(base, PhotoFileMetadata(rating: 3, orientation: 1, keywords: [])))
    }

    @Test func ignoresCaptureDate() {
        let a = PhotoFileMetadata(rating: 1, orientation: 1, keywords: [], captureDate: .now)
        let b = PhotoFileMetadata(rating: 1, orientation: 1, keywords: [], captureDate: nil)
        #expect(!MetadataSync.differs(a, b))
    }
}
