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

/// The raw XMP packet of a file, for format assertions.
private func xmpPacket(of url: URL) throws -> String {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let metadata = try #require(CGImageSourceCopyMetadataAtIndex(source, 0, nil))
    let data = try #require(CGImageMetadataCreateXMPData(metadata, nil)) as Data
    return String(decoding: data, as: UTF8.self)
}

struct MetadataWriterTests {
    private func tempJPEG(named name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name).jpg")
    }

    @Test func hierarchicalRoundTripAndMergePreservesEXIF() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJPEG(to: url, properties: [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2024:06:01 10:30:00"
            ] as [CFString: Any],
        ])

        try MetadataWriter.write(
            rating: 4, keywordPaths: [["PEOPLE", "ANNA"], ["TRIP"]], to: url
        )

        let metadata = MetadataReader.read(from: url)
        #expect(metadata.rating == 4)
        #expect(metadata.keywords == ["PEOPLE > ANNA", "TRIP"])
        // Orientation is not part of this write path any more.
        #expect(metadata.orientation == 1)
        // Merge mode: untouched metadata (EXIF capture date) survives.
        #expect(metadata.captureDate != nil)

        // Lightroom format: lr:hierarchicalSubject carries the paths, dc:subject
        // the flat, de-duplicated component list (parents included).
        let xmp = try xmpPacket(of: url)
        #expect(xmp.contains("xmlns:lr=\"http://ns.adobe.com/lightroom/1.0/\""))
        #expect(xmp.contains("<rdf:li>PEOPLE|ANNA</rdf:li>"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let tags = try #require(CGImageSourceCopyMetadataAtIndex(source, 0, nil))
        let subject = try #require(CGImageMetadataCopyTagWithPath(tags, nil, "dc:subject" as CFString))
        let flat = (CGImageMetadataTagCopyValue(subject) as? [AnyObject])?
            .compactMap { CGImageMetadataTagCopyValue($0 as! CGImageMetadataTag) as? String }
        #expect(flat == ["ANNA", "PEOPLE", "TRIP"])
        #expect(CGImageMetadataCopyTagWithPath(tags, nil, "lr:hierarchicalSubject" as CFString) != nil)
    }

    @Test func readsLegacyAngleBracketPathsFromDCSubject() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeXMPJPEG(to: url, rating: "2", subjects: ["PEOPLE > ANNA", "trip"])
        let metadata = MetadataReader.read(from: url)
        #expect(metadata.rating == 2)
        #expect(metadata.keywords == ["PEOPLE > ANNA", "TRIP"])
    }

    @Test func readsPipePathsFromDCSubjectWithoutHierarchicalTag() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeXMPJPEG(to: url, rating: nil, subjects: ["people|anna", "Places|Berlin|Mitte"])
        let metadata = MetadataReader.read(from: url)
        #expect(metadata.keywords == ["PEOPLE > ANNA", "PLACES > BERLIN > MITTE"])
    }

    @Test func readsFlatDCSubject() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeXMPJPEG(to: url, rating: nil, subjects: ["zoo", "Anna", "ZOO"])
        #expect(MetadataReader.read(from: url).keywords == ["ANNA", "ZOO"])
    }

    @Test func hierarchicalTagWinsOverFlatSubject() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        // Lightroom's own layout: flat leaves+parents in dc:subject, paths in lr:.
        try writeJPEG(to: url, properties: [:])
        try MetadataWriter.write(rating: 1, keywordPaths: [["PEOPLE", "ANNA"]], to: url)
        let metadata = MetadataReader.read(from: url)
        #expect(metadata.keywords == ["PEOPLE > ANNA"])  // not ANNA + PEOPLE
    }

    @Test func imagePixelsAreUntouched() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJPEG(to: url, properties: [:])
        let before = try pixelBytes(of: url)

        try MetadataWriter.write(rating: 5, keywordPaths: [["X"]], to: url)

        #expect(try pixelBytes(of: url) == before)
    }

    @Test func emptySetRoundTripWritesEmptyArraysAndIgnoresIPTC() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        // A stale IPTC Keywords block: with an XMP packet present it must
        // never be read back, even though dc:subject is empty.
        try writeJPEG(to: url, properties: [
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["STALE"]] as [CFString: Any],
        ])

        try MetadataWriter.write(rating: 3, keywordPaths: [["OLD"], ["STALE"]], to: url)
        try MetadataWriter.write(rating: 0, keywordPaths: [], to: url)

        let metadata = MetadataReader.read(from: url)
        #expect(metadata.rating == 0)
        #expect(metadata.keywords.isEmpty)
        let xmp = try xmpPacket(of: url)
        #expect(xmp.contains("<dc:subject>"))
        #expect(xmp.contains("<lr:hierarchicalSubject>"))
        #expect(!xmp.contains("STALE"))
    }

    @Test func iptcKeywordsOnlyWithoutXMPPacket() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJPEG(to: url, properties: [
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["legacy|path", "flat"]] as [CFString: Any],
        ])
        // No XMP at all → IPTC is the only source and is honoured.
        #expect(MetadataReader.read(from: url).keywords == ["FLAT", "LEGACY > PATH"])
    }

    @Test func orientationOnlyWriteKeepsRatingKeywords() throws {
        let url = tempJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJPEG(to: url, properties: [:])
        try MetadataWriter.write(rating: 2, keywordPaths: [["KEEP"]], to: url)
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

    @Test func unreadableSourceThrowsAndLeavesFileAlone() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-an-image.txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let content = Data("plain text".utf8)
        try content.write(to: url)

        #expect(throws: MetadataWriteError.self) {
            try MetadataWriter.write(rating: 1, keywordPaths: [], to: url)
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

    @Test func detectsRatingAndKeywordsOnly() {
        let base = PhotoFileMetadata(rating: 3, orientation: 1, keywords: ["A"])
        #expect(MetadataSync.differs(base, PhotoFileMetadata(rating: 4, orientation: 1, keywords: ["A"])))
        #expect(MetadataSync.differs(base, PhotoFileMetadata(rating: 3, orientation: 1, keywords: [])))
        // Orientation is library-only (Q5): not a file-sync attribute.
        #expect(!MetadataSync.differs(base, PhotoFileMetadata(rating: 3, orientation: 6, keywords: ["A"])))
    }

    @Test func ignoresCaptureDate() {
        let a = PhotoFileMetadata(rating: 1, orientation: 1, keywords: [], captureDate: .now)
        let b = PhotoFileMetadata(rating: 1, orientation: 1, keywords: [], captureDate: nil)
        #expect(!MetadataSync.differs(a, b))
    }
}
