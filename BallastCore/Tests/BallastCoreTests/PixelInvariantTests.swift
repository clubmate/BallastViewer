import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BallastCore

/// THE pixel invariant (CLAUDE.md "Pixel invariant"): no write path may ever
/// alter image data. This suite is the gate for every change that touches
/// `MetadataWriter` or adds a new way of writing an image file — extend it
/// for every new write path, never weaken it.
///
/// Two checks, both on a gradient + noise image (a flat test image can survive
/// a silent recompression unchanged and would prove nothing):
/// 1. the *compressed* image data — JPEG entropy-coded segment (SOS…EOI),
///    PNG IDAT chunks — is byte-identical before and after every write;
/// 2. the decoded pixels are identical.
/// Container bytes (XMP/EXIF blocks) may legitimately change.
struct PixelInvariantTests {
    // MARK: Fixture

    /// 320×240 gradient with per-pixel noise: every 8×8 JPEG block has
    /// unique content, so any re-encode changes the compressed bytes.
    private static func noisyGradient() -> CGImage {
        let width = 320, height = 240
        var seed: UInt32 = 0x9E37_79B9
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = Int(seed >> 24) % 81 - 40
                let i = (y * width + x) * 4
                pixels[i] = UInt8(clamping: x * 255 / width + noise)
                pixels[i + 1] = UInt8(clamping: y * 255 / height + noise)
                pixels[i + 2] = UInt8(clamping: (x + y) * 255 / (width + height) + noise)
                pixels[i + 3] = 255
            }
        }
        let context = pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )!
        }
        return context.makeImage()!
    }

    private func writeFixture(type: UTType) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(type.preferredFilenameExtension ?? "img")
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(
            destination, Self.noisyGradient(),
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    // MARK: Extractors

    /// JPEG: everything from the first SOS marker to the end — the Huffman
    /// coded scan, i.e. the actual compressed pixels.
    private static func jpegScan(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var i = 2
        while i + 3 < bytes.count {
            guard bytes[i] == 0xFF else { i += 1; continue }
            let marker = bytes[i + 1]
            if marker == 0xDA { return Data(bytes[i...]) }
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            i += 2 + length
        }
        return Data()
    }

    /// PNG: the concatenated IDAT chunks (the zlib-compressed pixels).
    private static func pngIDAT(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var i = 8
        var out = Data()
        while i + 8 <= bytes.count {
            let length = Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16
                | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            if bytes[i + 4..<i + 8].elementsEqual("IDAT".utf8) {
                out.append(contentsOf: bytes[i + 8..<i + 8 + length])
            }
            i += 12 + length
        }
        return out
    }

    private static func compressedImageData(of url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        let extracted = url.pathExtension == "png" ? pngIDAT(data) : jpegScan(data)
        #expect(!extracted.isEmpty, "extractor found no image data in \(url.lastPathComponent)")
        return extracted
    }

    private static func decodedPixels(of url: URL) throws -> Data {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var data = Data(count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    /// Runs `operation` and asserts both invariants against the state before.
    private func assertPixelsUntouched(_ url: URL, _ operation: () throws -> Void) throws {
        let compressedBefore = try Self.compressedImageData(of: url)
        let pixelsBefore = try Self.decodedPixels(of: url)
        try operation()
        #expect(try Self.compressedImageData(of: url) == compressedBefore, "compressed image data changed")
        #expect(try Self.decodedPixels(of: url) == pixelsBefore, "decoded pixels changed")
    }

    // MARK: Library write path (automatic write-through, Lightroom format)

    @Test(arguments: [UTType.jpeg, UTType.png])
    func libraryWriteKeepsImageData(type: UTType) throws {
        let url = try writeFixture(type: type)
        defer { try? FileManager.default.removeItem(at: url) }

        // Two passes with different values: the second rewrites an already
        // patched file, which is the common case after the first sync.
        try assertPixelsUntouched(url) {
            try MetadataWriter.write(rating: 5, keywordPaths: [["PEOPLE", "ANNA"], ["TRIP"]], to: url)
        }
        try assertPixelsUntouched(url) {
            try MetadataWriter.write(rating: 0, keywordPaths: [], to: url)
        }
    }

    /// Hierarchical keywords exercise the `lr:` namespace registration and
    /// the `rdf:Bag` tag creation — a distinct ImageIO code path from the
    /// plain `dc:subject` patch, so it gets its own gate.
    @Test(arguments: [UTType.jpeg, UTType.png])
    func hierarchicalKeywordWriteKeepsImageData(type: UTType) throws {
        let url = try writeFixture(type: type)
        defer { try? FileManager.default.removeItem(at: url) }

        let deep: [[String]] = [
            ["PLACES", "EUROPE", "BERLIN", "MITTE"],
            ["PEOPLE", "FAMILY", "ANNA"],
            ["PEOPLE", "FAMILY", "BEN"],
            ["EVENT", "WEDDING 2024"],
        ]
        try assertPixelsUntouched(url) {
            try MetadataWriter.write(rating: 3, keywordPaths: deep, to: url)
        }
        // The format landed (not a silent no-op write).
        let read = MetadataReader.read(from: url)
        #expect(read.keywords.contains("PLACES > EUROPE > BERLIN > MITTE"))
        #expect(read.keywords.count == 4)
        // Re-keying the hierarchy on an already-hierarchical file.
        try assertPixelsUntouched(url) {
            try MetadataWriter.write(rating: 1, keywordPaths: [["PEOPLE", "FAMILY", "ANNA"]], to: url)
        }
        #expect(MetadataReader.read(from: url).keywords == ["PEOPLE > FAMILY > ANNA"])
        // Back to an empty set — empty arrays, not a tag deletion.
        try assertPixelsUntouched(url) {
            try MetadataWriter.write(rating: 0, keywordPaths: [], to: url)
        }
        #expect(MetadataReader.read(from: url).keywords.isEmpty)
    }

    // MARK: BallastPicker write path (rotation written straight to the file)

    @Test(arguments: [UTType.jpeg, UTType.png])
    func pickerOrientationWriteKeepsImageData(type: UTType) throws {
        let url = try writeFixture(type: type)
        defer { try? FileManager.default.removeItem(at: url) }

        try assertPixelsUntouched(url) { try MetadataWriter.writeOrientation(6, to: url) }
        try assertPixelsUntouched(url) { try MetadataWriter.writeOrientation(8, to: url) }
        try assertPixelsUntouched(url) { try MetadataWriter.writeOrientation(1, to: url) }
    }

    /// Sanity check of the gate itself: a real re-encode MUST be detected,
    /// otherwise the assertions above prove nothing.
    @Test func detectorCatchesARecompression() throws {
        let url = try writeFixture(type: .jpeg)
        defer { try? FileManager.default.removeItem(at: url) }
        let before = try Self.compressedImageData(of: url)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        #expect(try Self.compressedImageData(of: url) != before)
    }
}
