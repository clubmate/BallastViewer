import Foundation
import GRDB
import Testing
@testable import BallastCore

/// Regression tests for the 2026-08 review fixes: Unicode normalisation,
/// id chunking, malformed keyword paths, parent-cycle guards and the shared
/// case folding.
@Suite struct RobustnessFixTests {
    @Test func decomposedKeywordDoesNotDuplicatePrecomposedOne() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let nfc = "MÜNCHEN"  // precomposed U+00DC
            let nfd = "MU\u{0308}NCHEN"  // U + combining diaeresis
            let first = try KeywordDAO.ensurePath([nfc], groupId: nil, in: db)
            let second = try KeywordDAO.ensurePath([nfd], groupId: nil, in: db)

            #expect(first == second)
            #expect(try KeywordRecord.fetchCount(db) == 1)
        }
    }

    @Test func normalizeKeywordsPrecomposesFileInput() {
        let result = MetadataReader.normalizeKeywords(["mu\u{0308}nchen", "MÜNCHEN"])
        #expect(result == ["MÜNCHEN"])
        #expect(result[0].unicodeScalars.count == "MÜNCHEN".unicodeScalars.count)
    }

    @Test func batchUpdatesSurviveMoreIdsThanOneChunk() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            var ids: [Int64] = []
            for index in 0..<(PhotoDAO.idChunkSize * 2 + 17) {
                ids.append(try insertPhoto(db, folderId: folderId, path: "/tmp/photos/p\(index).jpg"))
            }
            let keywordId = try KeywordDAO.ensurePath(["BULK"], groupId: nil, in: db)
            try PhotoDAO.assignKeyword(keywordId, toPhotoIds: ids, in: db)

            try PhotoDAO.setRating(4, forPhotoIds: ids, in: db)
            #expect(try PhotoRecord.filter(Column("rating") == 4).fetchCount(db) == ids.count)

            try PhotoDAO.setOrientation(6, forPhotoIds: ids, in: db)
            #expect(try PhotoRecord.filter(Column("orientation") == 6).fetchCount(db) == ids.count)

            try PhotoDAO.removeKeyword(keywordId, fromPhotoIds: ids, in: db)
            #expect(try PhotoKeywordRecord.fetchCount(db) == 0)
        }
    }

    @Test func emptyPathComponentsAreDropped() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            // "A >  > B" splits into ["A", "", "B"] — the empty part must not
            // become a node with an empty name mid-path.
            let leaf = try KeywordDAO.ensurePath(["A", "  ", "B"], groupId: nil, in: db)
            let tree = KeywordTree(records: try KeywordDAO.fetchAll(db))

            #expect(tree.path(of: leaf) == "A > B")
            #expect(try KeywordRecord.fetchCount(db) == 2)
        }
    }

    @Test func parentCycleDoesNotHangTreeWalks() {
        // Not creatable through the app, but a hand-edited DB can contain it.
        let tree = KeywordTree(records: [
            KeywordRecord(id: 1, parentId: 2, groupId: nil, name: "A"),
            KeywordRecord(id: 2, parentId: 1, groupId: 7, name: "B"),
        ])
        #expect(tree.pathComponents(of: 1) == ["B", "A"])
        #expect(tree.effectiveGroupId(of: 1) == 7)
    }

    @Test func ruleEngineAndSearchAgreeOnCaseFolding() {
        // "STRASSE" is what `uppercased()` stores for a typed "straße"; both
        // comparison paths must treat the fold-sensitive query identically.
        let facts = PhotoQueryFacts(keywordPaths: ["STRASSE"])
        let photo = PhotoRecord(folderId: 1, path: "/tmp/x.jpg")
        let rule = CollectionRuleRecord(
            collectionId: 1, type: "keyword", operation: "equals", value: "straße", sortOrder: 0
        )
        #expect(QueryEngine.matches(photo, facts: facts, rules: [rule], matchAll: true))
        #expect(SearchFilter.matches(filename: "x.jpg", keywordPaths: ["STRASSE"], query: "straße"))
    }
}
