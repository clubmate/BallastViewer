import CoreGraphics
import Foundation
import GRDB
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BallastCore

// MARK: - Fixtures

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bv-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeTinyImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    return context.makeImage()!
}

/// Writes a JPEG carrying classic ImageIO properties (IPTC, EXIF, orientation).
func writeJPEG(to url: URL, properties: [CFString: Any]) throws {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, makeTinyImage(), properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
}

/// Writes a JPEG carrying XMP metadata (xmp:Rating, dc:subject).
func writeXMPJPEG(to url: URL, rating: String?, subjects: [String]?) throws {
    let metadata = CGImageMetadataCreateMutable()
    if let rating {
        #expect(CGImageMetadataSetValueWithPath(metadata, nil, "xmp:Rating" as CFString, rating as CFTypeRef))
    }
    if let subjects {
        #expect(CGImageMetadataSetValueWithPath(metadata, nil, "dc:subject" as CFString, subjects as CFTypeRef))
    }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImageAndMetadata(destination, makeTinyImage(), metadata, nil)
    #expect(CGImageDestinationFinalize(destination))
}

// MARK: - FolderScanner

@Suite struct FolderScannerTests {
    @Test func scanFiltersExtensionsHiddenFilesAndRecursesOnDemand() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        for name in ["a.jpg", "B.JPG", "c.txt", ".hidden.jpg"] {
            FileManager.default.createFile(atPath: root.appendingPathComponent(name).path, contents: Data())
        }
        FileManager.default.createFile(atPath: sub.appendingPathComponent("d.png").path, contents: Data())

        let recursive = FolderScanner.scan(root, recursive: true).map(\.lastPathComponent)
        #expect(recursive.sorted() == ["B.JPG", "a.jpg", "d.png"])

        let flat = FolderScanner.scan(root, recursive: false).map(\.lastPathComponent)
        #expect(flat.sorted() == ["B.JPG", "a.jpg"])
    }
}

// MARK: - MetadataReader

@Suite struct MetadataReaderTests {
    @Test func unreadableFileIsEmptySuccess() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("garbage.jpg")
        try Data("not an image".utf8).write(to: url)

        #expect(MetadataReader.read(from: url) == PhotoFileMetadata())
    }

    @Test func readsIPTCFallbackClampsRatingAndNormalizesKeywords() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("iptc.jpg")
        try writeJPEG(to: url, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCKeywords: ["anna", "ZOO", "Anna"],
                kCGImagePropertyIPTCStarRating: 7,
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2024:06:01 10:30:00",
            ],
        ])

        let result = MetadataReader.read(from: url)
        #expect(result.orientation == 6)
        #expect(result.rating == 5)  // D5: clamped, not 7
        #expect(result.keywords == ["ANNA", "ZOO"])  // uppercased, deduped, sorted
        #expect(result.captureDate == MetadataReader.parseEXIFDate("2024:06:01 10:30:00"))
        #expect(result.captureDate != nil)
    }

    @Test func xmpBeatsIPTCOnRead() throws {
        // D1's read half: xmp:Rating / dc:subject win over IPTC.
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("xmp.jpg")
        try writeXMPJPEG(to: url, rating: "4", subjects: ["PEOPLE > ANNA", "match"])

        let result = MetadataReader.read(from: url)
        #expect(result.rating == 4)
        #expect(result.keywords == ["MATCH", "PEOPLE > ANNA"])
    }
}

// MARK: - ImportDAO

@Suite struct ImportDAOTests {
    @Test func importCreatesBatchAssignsKeywordsAndDedupes() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folder = try ImportDAO.registerFolder(path: "/shoot", bookmark: nil, recursive: true, in: db)
            let items = [
                ImportItem(path: "/shoot/a.jpg", metadata: PhotoFileMetadata(rating: 3, keywords: ["PEOPLE > ANNA"])),
                ImportItem(path: "/shoot/b.jpg", metadata: PhotoFileMetadata()),
            ]

            let first = try ImportDAO.importPhotos(items, folderId: folder.id!, in: db)
            #expect(first.added == 2 && first.skipped == 0 && first.batchId != nil)

            let meta = try LibraryMetaRecord.fetchOne(db)
            #expect(meta?.lastImportBatchId == first.batchId)

            // Hierarchical keyword became a node chain assigned to the photo.
            let tree = KeywordTree(records: try KeywordDAO.fetchAll(db))
            #expect(tree.allPaths() == ["PEOPLE", "PEOPLE > ANNA"])
            #expect(try PhotoKeywordRecord.fetchCount(db) == 1)

            // Q7: rescan finding nothing new — no batch, lastImportBatchId untouched.
            let second = try ImportDAO.importPhotos(items, folderId: folder.id!, in: db)
            #expect(second == ImportResult(added: 0, skipped: 2, batchId: nil))
            #expect(try ImportBatchRecord.fetchCount(db) == 1)
            #expect(try LibraryMetaRecord.fetchOne(db)?.lastImportBatchId == first.batchId)
        }
    }

    @Test func registerFolderIsIdempotentByPath() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let first = try ImportDAO.registerFolder(path: "/shoot", bookmark: nil, recursive: true, in: db)
            let second = try ImportDAO.registerFolder(path: "/shoot", bookmark: nil, recursive: false, in: db)
            #expect(first.id == second.id)
            #expect(try FolderRecord.fetchCount(db) == 1)
            #expect(try FolderRecord.fetchOne(db)?.recursive == false)
        }
    }

    @Test func removingTripSparesTrip2024() throws {
        // D4: removal is by folder membership, never by path prefix.
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let trip = try ImportDAO.registerFolder(path: "/Photos/Trip", bookmark: nil, recursive: true, in: db)
            let trip2024 = try ImportDAO.registerFolder(path: "/Photos/Trip2024", bookmark: nil, recursive: true, in: db)
            _ = try ImportDAO.importPhotos(
                [ImportItem(path: "/Photos/Trip/a.jpg", metadata: .init())],
                folderId: trip.id!, in: db
            )
            _ = try ImportDAO.importPhotos(
                [ImportItem(path: "/Photos/Trip2024/b.jpg", metadata: .init())],
                folderId: trip2024.id!, in: db
            )

            let removed = try ImportDAO.removeFolder(trip.id!, in: db)
            #expect(removed == 1)

            let survivors = try PhotoRecord.fetchAll(db)
            #expect(survivors.map(\.path) == ["/Photos/Trip2024/b.jpg"])
        }
    }
}
