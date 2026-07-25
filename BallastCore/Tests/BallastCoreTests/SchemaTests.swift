import Foundation
import GRDB
import Testing
@testable import BallastCore

/// Fresh in-memory database, migrated and seeded like a newly created library.
func makeTestDatabase() throws -> DatabaseQueue {
    let dbQueue = try DatabaseQueue()
    try LibrarySchema.migrator.migrate(dbQueue)
    try dbQueue.write { try LibrarySchema.seed($0) }
    return dbQueue
}

@discardableResult
func insertFolder(_ db: Database, path: String = "/tmp/photos") throws -> Int64 {
    var folder = FolderRecord(path: path)
    try folder.insert(db)
    return folder.id!
}

@discardableResult
func insertPhoto(_ db: Database, folderId: Int64, path: String, rating: Int = 0) throws -> Int64 {
    var photo = PhotoRecord(folderId: folderId, path: path, rating: rating)
    try photo.insert(db)
    return photo.id!
}

@Suite struct SchemaTests {
    @Test func migrationCreatesAllTables() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.read { db in
            for table in [
                "libraryMeta", "folder", "importBatch", "photo", "keywordGroup",
                "keyword", "photoKeyword", "smartGroup", "smartCollection", "collectionRule",
            ] {
                let exists = try db.tableExists(table)
                #expect(exists, "missing table \(table)")
            }
        }
    }

    @Test func seedCreatesMetaAndSixDefaultGroups() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.read { db in
            let meta = try LibraryMetaRecord.fetchOne(db)
            #expect(meta != nil)
            #expect(UUID(uuidString: meta?.libraryUUID ?? "") != nil)

            let groups = try KeywordDAO.fetchGroups(db)
            let expected: [(String, String)] = [
                ("YEAR", "#007AFF"), ("META", "#34C759"), ("PEOPLE", "#BF5AF2"),
                ("LOCATION", "#FF3B30"), ("EVENT", "#AF52DE"), ("MISC", "#FF9500"),
            ]
            #expect(groups.map(\.name) == expected.map(\.0))
            #expect(groups.map(\.color) == expected.map(\.1))
            #expect(groups.map(\.sortOrder) == Array(0..<6))
        }
    }

    @Test func photoRatingOutsideRangeIsRejected() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            #expect(throws: (any Error).self) {
                try insertPhoto(db, folderId: folderId, path: "/tmp/photos/a.jpg", rating: 7)
            }
        }
    }

    @Test func duplicatePhotoPathIsRejected() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            try insertPhoto(db, folderId: folderId, path: "/tmp/photos/a.jpg")
            #expect(throws: (any Error).self) {
                try insertPhoto(db, folderId: folderId, path: "/tmp/photos/a.jpg")
            }
        }
    }

    @Test func deletingFolderCascadesToPhotosAndAssignments() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            let photoId = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/a.jpg")
            let keywordId = try KeywordDAO.ensurePath(["ANNA"], groupId: nil, in: db)
            try PhotoDAO.assignKeyword(keywordId, toPhotoIds: [photoId], in: db)

            try FolderRecord.deleteOne(db, key: folderId)

            #expect(try PhotoRecord.fetchCount(db) == 0)
            #expect(try PhotoKeywordRecord.fetchCount(db) == 0)
            // The keyword itself survives — only the assignment dies.
            #expect(try KeywordRecord.fetchCount(db) == 1)
        }
    }

    @Test func deletingKeywordGroupNullsMembersInsteadOfOrphaning() throws {
        // C3: group delete must not leave dangling groupIds.
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let group = try KeywordDAO.createGroup(name: "TEST", color: "#FF0000", in: db)
            let keywordId = try KeywordDAO.ensurePath(["ANNA"], groupId: group.id, in: db)

            try KeywordDAO.deleteGroup(group.id!, in: db)

            let keyword = try KeywordRecord.fetchOne(db, key: keywordId)
            #expect(keyword != nil)
            #expect(keyword?.groupId == nil)
        }
    }

    @Test func deletingCollectionCascadesToRules() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let group = try CollectionDAO.createGroup(name: "Best Of", in: db)
            let collection = try CollectionDAO.createCollection(name: "Keepers", inGroup: group.id!, in: db)
            try CollectionDAO.saveRules(
                [(type: "rating", operation: "greaterThan", value: "3")],
                forCollection: collection.id!,
                in: db
            )
            #expect(try CollectionRuleRecord.fetchCount(db) == 1)

            try CollectionDAO.deleteGroup(group.id!, in: db)

            #expect(try SmartCollectionRecord.fetchCount(db) == 0)
            #expect(try CollectionRuleRecord.fetchCount(db) == 0)
        }
    }

    @Test func duplicateKeywordNamesAreRejectedPerLevel() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let peopleId = try KeywordDAO.ensurePath(["PEOPLE"], groupId: nil, in: db)
            _ = try KeywordDAO.ensurePath(["PEOPLE", "ANNA"], groupId: nil, in: db)

            // Same name under the same parent → rejected at the constraint level.
            var duplicateChild = KeywordRecord(parentId: peopleId, groupId: nil, name: "ANNA")
            #expect(throws: (any Error).self) { try duplicateChild.insert(db) }

            var duplicateRoot = KeywordRecord(parentId: nil, groupId: nil, name: "PEOPLE")
            #expect(throws: (any Error).self) { try duplicateRoot.insert(db) }

            // Same name under a different parent is fine.
            let eventId = try KeywordDAO.ensurePath(["EVENT"], groupId: nil, in: db)
            var annaUnderEvent = KeywordRecord(parentId: eventId, groupId: nil, name: "ANNA")
            try annaUnderEvent.insert(db)
            #expect(try KeywordRecord.fetchCount(db) == 4)
        }
    }
}

@Suite struct LibraryDatabaseTests {
    private func temporaryPackageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(LibraryDatabase.packageExtension)
    }

    @Test func createOpensSeededLibraryAndRejectsDuplicates() throws {
        let url = temporaryPackageURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let library = try LibraryDatabase.create(at: url)
        let groupCount = try library.pool.read { try KeywordGroupRecord.fetchCount($0) }
        #expect(groupCount == 6)

        #expect(throws: LibraryDatabaseError.alreadyExists(url)) {
            _ = try LibraryDatabase.create(at: url)
        }

        // Reopen works and keeps the seeded content.
        let reopened = try LibraryDatabase.open(at: url)
        let snapshot = try reopened.pool.read { try LibrarySnapshot.load($0) }
        #expect(snapshot.keywordGroups.count == 6)
        #expect(snapshot.photos.isEmpty)
    }

    @Test func openRejectsNonLibraries() throws {
        let url = temporaryPackageURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        #expect(throws: LibraryDatabaseError.notALibrary(url)) {
            _ = try LibraryDatabase.open(at: url)
        }
    }

    @Test func openThrowsOnCorruptDatabase() throws {
        // Spec §4.2 fix: a corrupt file must surface an error, never fail silently.
        let url = temporaryPackageURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("this is not a sqlite database".utf8)
            .write(to: url.appendingPathComponent("library.sqlite"))

        #expect(throws: (any Error).self) {
            _ = try LibraryDatabase.open(at: url)
        }
    }
}
