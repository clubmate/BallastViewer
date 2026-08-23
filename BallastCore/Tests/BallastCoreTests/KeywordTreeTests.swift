import Foundation
import GRDB
import Testing
@testable import BallastCore

@Suite struct KeywordTreeTests {
    @Test func ensurePathWithOnlyBlankComponentsThrowsEmptyName() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            #expect(throws: KeywordDAOError.emptyName) {
                try KeywordDAO.ensurePath(["  ", "", "\n"], groupId: nil, in: db)
            }
            #expect(throws: KeywordDAOError.emptyName) {
                try KeywordDAO.ensurePath([], groupId: nil, in: db)
            }
            let count = try KeywordRecord.fetchCount(db)
            #expect(count == 0)
        }
    }

    @Test func deltaDerivationsNormaliseNamesLikeTheDAO() {
        var people = KeywordRecord(parentId: nil, groupId: nil, name: "PEOPLE")
        people.id = 1
        let tree = KeywordTree(records: [people])
        let renamed = tree.renaming(1, to: "  folks\u{0308} ")  // decomposed diaeresis
        #expect(renamed.node(1)?.name == "FOLKS\u{0308}".precomposedStringWithCanonicalMapping)
        #expect(renamed.node(1)?.name == KeywordDAO.normalize("folks\u{0308}"))

        var anna = KeywordRecord(parentId: 1, groupId: nil, name: " anna ")
        anna.id = 2
        var bob = KeywordRecord(parentId: 1, groupId: nil, name: "bob\n")
        bob.id = 3
        let grown = tree.inserting(anna).inserting(contentsOf: [bob])
        #expect(grown.node(2)?.name == "ANNA")
        #expect(grown.node(3)?.name == "BOB")
        #expect(grown.path(of: 2) == "PEOPLE > ANNA")
        #expect(grown.find(pathComponents: ["people", "bob"]) == 3)
    }

    @Test func settingGroupMovesNodeAndInheritingDescendants() {
        var people = KeywordRecord(parentId: nil, groupId: nil, name: "PEOPLE")
        people.id = 1
        var anna = KeywordRecord(parentId: 1, groupId: nil, name: "ANNA")
        anna.id = 2
        var bob = KeywordRecord(parentId: 1, groupId: 9, name: "BOB")
        bob.id = 3
        let ungrouped = KeywordTree(records: [people, anna, bob])
        #expect(ungrouped.effectiveGroupId(of: 1) == nil)
        #expect(ungrouped.rootIds.filter { ungrouped.effectiveGroupId(of: $0) == nil } == [1])

        let grouped = ungrouped.settingGroup(7, of: 1)
        #expect(grouped.node(1)?.groupId == 7)
        #expect(grouped.effectiveGroupId(of: 2) == 7)  // inherits
        #expect(grouped.effectiveGroupId(of: 3) == 9)  // own group wins
        #expect(grouped.path(of: 2) == "PEOPLE > ANNA")  // paths untouched

        let freed = grouped.settingGroup(nil, of: 1)
        #expect(freed.effectiveGroupId(of: 1) == nil)
        #expect(freed.effectiveGroupId(of: 2) == nil)
    }

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

            let count = try KeywordRecord.fetchCount(db)
            #expect(count == 0)
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
