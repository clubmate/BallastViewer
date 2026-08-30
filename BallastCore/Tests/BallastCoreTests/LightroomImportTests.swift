import Foundation
import GRDB
import Testing
@testable import BallastCore

/// A minimal on-disk `.lrcat` stand-in: just the six tables the reader touches,
/// filled by the test. Real catalogs carry dozens more — the reader must not care.
private func makeLightroomCatalog(
    _ configure: @escaping (Database) throws -> Void
) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lrcat-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("test.lrcat")
    let dbQueue = try DatabaseQueue(path: url.path)
    try dbQueue.write { db in
        try db.execute(sql: """
            CREATE TABLE AgLibraryRootFolder (id_local INTEGER PRIMARY KEY, absolutePath TEXT);
            CREATE TABLE AgLibraryFolder (id_local INTEGER PRIMARY KEY, rootFolder INTEGER, pathFromRoot TEXT);
            CREATE TABLE AgLibraryFile (id_local INTEGER PRIMARY KEY, folder INTEGER, idx_filename TEXT);
            CREATE TABLE Adobe_images (id_local INTEGER PRIMARY KEY, rootFile INTEGER, rating REAL);
            CREATE TABLE AgLibraryKeyword (id_local INTEGER PRIMARY KEY, parent INTEGER, name TEXT);
            CREATE TABLE AgLibraryKeywordImage (id_local INTEGER PRIMARY KEY, image INTEGER, tag INTEGER);
            """)
        try configure(db)
    }
    try dbQueue.close()
    return url
}

@Suite struct LightroomCatalogReaderTests {
    @Test func assemblesPathsRatingsAndKeywordHierarchy() throws {
        let url = try makeLightroomCatalog { db in
            try db.execute(sql: """
                INSERT INTO AgLibraryRootFolder VALUES (1, '/Users/anna/Pictures/');
                INSERT INTO AgLibraryFolder VALUES (10, 1, '2020/rome/');
                INSERT INTO AgLibraryFolder VALUES (11, 1, '');
                INSERT INTO AgLibraryFile VALUES (100, 10, 'IMG_0001.jpg');
                INSERT INTO AgLibraryFile VALUES (101, 11, 'IMG_0002.jpg');
                -- Lightroom's invisible keyword root has a NULL name.
                INSERT INTO AgLibraryKeyword VALUES (200, NULL, NULL);
                INSERT INTO AgLibraryKeyword VALUES (201, 200, 'people');
                INSERT INTO AgLibraryKeyword VALUES (202, 201, 'anna');
                INSERT INTO AgLibraryKeyword VALUES (203, 200, 'rome');
                INSERT INTO Adobe_images VALUES (300, 100, 3.0);
                INSERT INTO Adobe_images VALUES (301, 101, NULL);
                INSERT INTO AgLibraryKeywordImage VALUES (400, 300, 202);
                INSERT INTO AgLibraryKeywordImage VALUES (401, 300, 203);
                """)
        }
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let entries = try LightroomCatalogReader.read(at: url)
        #expect(entries.count == 2)

        let first = try #require(entries.first { $0.path.hasSuffix("IMG_0001.jpg") })
        #expect(first.path == "/Users/anna/Pictures/2020/rome/IMG_0001.jpg")
        #expect(first.rating == 3)
        #expect(first.keywordPaths.contains(["people", "anna"]))
        #expect(first.keywordPaths.contains(["rome"]))

        let second = try #require(entries.first { $0.path.hasSuffix("IMG_0002.jpg") })
        #expect(second.path == "/Users/anna/Pictures/IMG_0002.jpg")
        #expect(second.rating == nil)
        #expect(second.keywordPaths.isEmpty)
    }

    @Test func mergesVirtualCopiesOfTheSameFile() throws {
        let url = try makeLightroomCatalog { db in
            try db.execute(sql: """
                INSERT INTO AgLibraryRootFolder VALUES (1, '/pics/');
                INSERT INTO AgLibraryFolder VALUES (10, 1, '');
                INSERT INTO AgLibraryFile VALUES (100, 10, 'a.jpg');
                INSERT INTO AgLibraryKeyword VALUES (200, NULL, NULL);
                INSERT INTO AgLibraryKeyword VALUES (201, 200, 'sun');
                INSERT INTO AgLibraryKeyword VALUES (202, 200, 'sea');
                -- master rated 2, virtual copy rated 4 with an extra keyword
                INSERT INTO Adobe_images VALUES (300, 100, 2.0);
                INSERT INTO Adobe_images VALUES (301, 100, 4.0);
                INSERT INTO AgLibraryKeywordImage VALUES (400, 300, 201);
                INSERT INTO AgLibraryKeywordImage VALUES (401, 301, 202);
                """)
        }
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let entries = try LightroomCatalogReader.read(at: url)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.rating == 4)
        #expect(entry.keywordPaths.contains(["sun"]))
        #expect(entry.keywordPaths.contains(["sea"]))
    }

    @Test func rejectsADatabaseWithoutLightroomTables() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lrcat-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("not-a-catalog.lrcat")
        let dbQueue = try DatabaseQueue(path: url.path)
        try dbQueue.write { try $0.execute(sql: "CREATE TABLE something (id INTEGER)") }
        try dbQueue.close()

        #expect(throws: LightroomCatalogError.notALightroomCatalog) {
            try LightroomCatalogReader.read(at: url)
        }
    }
}

@Suite struct LightroomMatcherTests {
    private func entry(_ path: String, rating: Int? = nil) -> LightroomPhotoEntry {
        LightroomPhotoEntry(path: path, rating: rating)
    }

    @Test func matchesByExactPathCaseInsensitively() {
        let result = LightroomMatcher.match(
            entries: [entry("/Pics/Rome/IMG_1.JPG")],
            photos: [LightroomLibraryPhoto(id: 7, path: "/pics/rome/img_1.jpg")]
        )
        #expect(result.matches.map(\.photoId) == [7])
        #expect(result.pathMatches == 1)
        #expect(result.filenameMatches == 0)
        #expect(result.unmatched == 0)
        #expect(result.ambiguous == 0)
    }

    @Test func fallsBackToUniqueFilenameForMovedFiles() {
        let result = LightroomMatcher.match(
            entries: [entry("/old/place/IMG_2.jpg")],
            photos: [LightroomLibraryPhoto(id: 3, path: "/new/home/IMG_2.jpg")]
        )
        #expect(result.matches.map(\.photoId) == [3])
        #expect(result.filenameMatches == 1)
        #expect(result.pathMatches == 0)
    }

    @Test func skipsAmbiguousFilenamesAndCountsUnmatched() {
        let result = LightroomMatcher.match(
            entries: [
                entry("/old/a/IMG_3.jpg"),
                entry("/old/b/IMG_3.jpg"),
                entry("/old/c/gone.jpg"),
            ],
            photos: [
                LightroomLibraryPhoto(id: 1, path: "/new/x/IMG_3.jpg"),
                LightroomLibraryPhoto(id: 2, path: "/new/y/other.jpg"),
            ]
        )
        // Two catalog entries share IMG_3.jpg — neither may claim the photo.
        #expect(result.matches.isEmpty)
        #expect(result.ambiguous == 2)
        #expect(result.unmatched == 1)
    }

    @Test func ambiguousLibrarySideIsSkippedToo() {
        let result = LightroomMatcher.match(
            entries: [entry("/old/IMG_4.jpg")],
            photos: [
                LightroomLibraryPhoto(id: 1, path: "/new/x/IMG_4.jpg"),
                LightroomLibraryPhoto(id: 2, path: "/new/y/IMG_4.jpg"),
            ]
        )
        #expect(result.matches.isEmpty)
        #expect(result.ambiguous == 1)
    }

    @Test func pathMatchedPhotoIsNotAFilenameFallbackTarget() {
        // Entry A owns photo 1 by path; entry B shares the filename but must
        // not steal photo 1 through the fallback.
        let result = LightroomMatcher.match(
            entries: [
                entry("/pics/IMG_5.jpg", rating: 1),
                entry("/elsewhere/IMG_5.jpg", rating: 5),
            ],
            photos: [LightroomLibraryPhoto(id: 1, path: "/pics/IMG_5.jpg")]
        )
        #expect(result.pathMatches == 1)
        #expect(result.matches.count == 1)
        #expect(result.matches[0].entry.rating == 1)
        #expect(result.unmatched == 1)
    }
}

@Suite struct LightroomMergeTests {
    @Test func appliesRatingsAndKeywordsAndFlagsOnlyChangedPhotos() throws {
        let dbQueue = try makeTestDatabase()
        let (photoA, photoB) = try dbQueue.write { db -> (Int64, Int64) in
            let folderId = try insertFolder(db)
            let a = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/a.jpg")
            let b = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/b.jpg", rating: 2)
            return (a, b)
        }

        let matches = [
            LightroomMatch(
                photoId: photoA,
                entry: LightroomPhotoEntry(
                    path: "/tmp/photos/a.jpg", rating: 4,
                    keywordPaths: [["people", "anna"], ["rome"]]
                )
            ),
            // B: same rating as stored, no keywords → must stay untouched.
            LightroomMatch(
                photoId: photoB,
                entry: LightroomPhotoEntry(path: "/tmp/photos/b.jpg", rating: 2)
            ),
        ]
        let summary = try dbQueue.write { try LightroomImportDAO.merge(matches, in: $0) }

        #expect(summary.changedPhotoIds == [photoA])
        #expect(summary.ratingsApplied == 1)
        #expect(summary.assignmentsAdded == 2)
        #expect(summary.keywordsCreated == 3)  // PEOPLE, ANNA, ROME

        try dbQueue.read { db in
            let a = try PhotoRecord.fetchOne(db, key: photoA)
            #expect(a?.rating == 4)
            #expect(a?.needsFileWrite == true)
            let b = try PhotoRecord.fetchOne(db, key: photoB)
            #expect(b?.rating == 2)
            #expect(b?.needsFileWrite == false)
            // Keywords land UPPERCASE with the hierarchy intact.
            let names = try String.fetchAll(db, sql: "SELECT name FROM keyword ORDER BY name")
            #expect(names == ["ANNA", "PEOPLE", "ROME"])
            let anna = try KeywordRecord.filter(Column("name") == "ANNA").fetchOne(db)
            let people = try KeywordRecord.filter(Column("name") == "PEOPLE").fetchOne(db)
            #expect(anna?.parentId == people?.id)
            let assigned = try Int64.fetchAll(
                db, sql: "SELECT keywordId FROM photoKeyword WHERE photoId = ?",
                arguments: [photoA]
            )
            let rome = try KeywordRecord.filter(Column("name") == "ROME").fetchOne(db)
            #expect(Set(assigned) == Set([anna?.id, rome?.id].compactMap { $0 }))
        }
    }

    @Test func nilLightroomRatingLeavesLibraryRatingAlone() throws {
        let dbQueue = try makeTestDatabase()
        let photoId = try dbQueue.write { db -> Int64 in
            let folderId = try insertFolder(db)
            return try insertPhoto(db, folderId: folderId, path: "/tmp/photos/c.jpg", rating: 5)
        }
        let matches = [LightroomMatch(
            photoId: photoId,
            entry: LightroomPhotoEntry(path: "/tmp/photos/c.jpg", rating: nil,
                                       keywordPaths: [["sea"]])
        )]
        let summary = try dbQueue.write { try LightroomImportDAO.merge(matches, in: $0) }
        #expect(summary.ratingsApplied == 0)
        try dbQueue.read { db in
            let rating = try PhotoRecord.fetchOne(db, key: photoId)?.rating
            #expect(rating == 5)
        }
    }

    @Test func rerunningTheSameMergeIsANoOp() throws {
        let dbQueue = try makeTestDatabase()
        let photoId = try dbQueue.write { db -> Int64 in
            let folderId = try insertFolder(db)
            return try insertPhoto(db, folderId: folderId, path: "/tmp/photos/d.jpg")
        }
        let matches = [LightroomMatch(
            photoId: photoId,
            entry: LightroomPhotoEntry(path: "/tmp/photos/d.jpg", rating: 3,
                                       keywordPaths: [["people", "anna"]])
        )]
        _ = try dbQueue.write { try LightroomImportDAO.merge(matches, in: $0) }
        // Simulate the write-through having caught up.
        try dbQueue.write { try PhotoDAO.setNeedsFileWrite(false, forPhotoIds: [photoId], in: $0) }

        let second = try dbQueue.write { try LightroomImportDAO.merge(matches, in: $0) }
        #expect(second == LightroomMergeSummary())
        try dbQueue.read { db in
            // The crucial bit: an unchanged photo is NOT re-flagged for a file write.
            let needsFileWrite = try PhotoRecord.fetchOne(db, key: photoId)?.needsFileWrite
            #expect(needsFileWrite == false)
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM keyword") ?? -1
            #expect(count == 2)
        }
    }

    @Test func mergeSkipsPhotosDeletedSinceTheMatch() throws {
        let dbQueue = try makeTestDatabase()
        let matches = [LightroomMatch(
            photoId: 999,
            entry: LightroomPhotoEntry(path: "/tmp/photos/gone.jpg", rating: 4)
        )]
        let summary = try dbQueue.write { try LightroomImportDAO.merge(matches, in: $0) }
        #expect(summary == LightroomMergeSummary())
    }

    @Test func existingKeywordAssignmentIsNotDuplicated() throws {
        let dbQueue = try makeTestDatabase()
        let photoId = try dbQueue.write { db -> Int64 in
            let folderId = try insertFolder(db)
            let id = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/e.jpg")
            let keywordId = try KeywordDAO.ensurePath(["ROME"], groupId: nil, in: db)
            try PhotoDAO.assignKeyword(keywordId, toPhotoIds: [id], in: db)
            return id
        }
        let matches = [LightroomMatch(
            photoId: photoId,
            entry: LightroomPhotoEntry(path: "/tmp/photos/e.jpg",
                                       keywordPaths: [["rome"], ["sea"]])
        )]
        let summary = try dbQueue.write { try LightroomImportDAO.merge(matches, in: $0) }
        #expect(summary.assignmentsAdded == 1)
        #expect(summary.keywordsCreated == 1)
        try dbQueue.read { db in
            let count = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM photoKeyword WHERE photoId = ?",
                arguments: [photoId]
            )
            #expect(count == 2)
        }
    }
}
