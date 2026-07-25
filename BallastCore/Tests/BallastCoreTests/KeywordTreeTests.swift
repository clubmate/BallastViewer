import Foundation
import GRDB
import Testing
@testable import BallastCore

@Suite struct KeywordTreeTests {
    @Test func ensurePathCreatesChainOnceAndReturnsLeaf() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let annaId = try KeywordDAO.ensurePath(["People", "team", "Anna"], groupId: nil, in: db)
            let again = try KeywordDAO.ensurePath(["PEOPLE", "TEAM", "ANNA"], groupId: nil, in: db)

            #expect(annaId == again)
            #expect(try KeywordRecord.fetchCount(db) == 3)

            let tree = KeywordTree(records: try KeywordDAO.fetchAll(db))
            #expect(tree.path(of: annaId) == "PEOPLE > TEAM > ANNA")
        }
    }

    @Test func renamePropagatesToDerivedPaths() throws {
        // C4 — the pivotal fix: rename is one UPDATE, every derived path follows.
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let annaId = try KeywordDAO.ensurePath(["PEOPLE", "TEAM", "ANNA"], groupId: nil, in: db)
            let teamId = KeywordTree(records: try KeywordDAO.fetchAll(db))
                .find(pathComponents: ["PEOPLE", "TEAM"])!

            try KeywordDAO.rename(teamId, to: "staff", in: db)

            let tree = KeywordTree(records: try KeywordDAO.fetchAll(db))
            #expect(tree.path(of: annaId) == "PEOPLE > STAFF > ANNA")
        }
    }

    @Test func deleteSubtreeRemovesDescendantsAndAssignments() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            let photoId = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/a.jpg")
            let annaId = try KeywordDAO.ensurePath(["PEOPLE", "TEAM", "ANNA"], groupId: nil, in: db)
            try PhotoDAO.assignKeyword(annaId, toPhotoIds: [photoId], in: db)

            let tree = KeywordTree(records: try KeywordDAO.fetchAll(db))
            let peopleId = tree.find(pathComponents: ["PEOPLE"])!
            try KeywordDAO.deleteSubtree(peopleId, in: db)

            #expect(try KeywordRecord.fetchCount(db) == 0)
            #expect(try PhotoKeywordRecord.fetchCount(db) == 0)
            #expect(try PhotoRecord.fetchCount(db) == 1)
        }
    }

    @Test func treeOrderingAndTraversal() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            try KeywordDAO.ensurePath(["ZEBRA"], groupId: nil, in: db)
            try KeywordDAO.ensurePath(["PEOPLE", "TEAM", "ANNA"], groupId: nil, in: db)
            try KeywordDAO.ensurePath(["PEOPLE", "BOB"], groupId: nil, in: db)

            let tree = KeywordTree(records: try KeywordDAO.fetchAll(db))

            // Siblings name-sorted (Q19); depth-first offers every node (Q17).
            #expect(tree.allPaths() == [
                "PEOPLE", "PEOPLE > BOB", "PEOPLE > TEAM", "PEOPLE > TEAM > ANNA", "ZEBRA",
            ])
        }
    }

    @Test func firstMatchIsDepthFirstAndCaseInsensitive() throws {
        // Q16: first match wins in depth-first order over the name-sorted tree.
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let annaUnderApple = try KeywordDAO.ensurePath(["APPLE", "ANNA"], groupId: nil, in: db)
            try KeywordDAO.ensurePath(["ZOO", "ANNA"], groupId: nil, in: db)

            let tree = KeywordTree(records: try KeywordDAO.fetchAll(db))
            #expect(tree.firstMatch(named: "anna") == annaUnderApple)
            #expect(tree.firstMatch(named: "missing") == nil)
        }
    }
}
