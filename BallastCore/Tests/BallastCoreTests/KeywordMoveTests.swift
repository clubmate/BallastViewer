import Foundation
import GRDB
import Testing
@testable import BallastCore

/// U36: the dropdown's explicit "Create" row — offered exactly when the
/// input as an EXACT path does not exist, the escape from Q16.
@Suite struct KeywordCreateOptionTests {
    private func makeTree(_ paths: [[String]]) -> KeywordTree {
        var records: [KeywordRecord] = []
        var nextId: Int64 = 1
        var idByPath: [String: Int64] = [:]
        for path in paths {
            var parent: Int64?
            var walked: [String] = []
            for name in path {
                walked.append(name)
                let key = walked.joined(separator: ">")
                if let existing = idByPath[key] {
                    parent = existing
                } else {
                    records.append(KeywordRecord(id: nextId, parentId: parent, groupId: nil, name: name))
                    idByPath[key] = nextId
                    parent = nextId
                    nextId += 1
                }
            }
        }
        return KeywordTree(records: records)
    }

    @Test func offeredWhenOnlyANestedNamesakeExists() {
        let tree = makeTree([["JAHRE", "2008"]])
        #expect(KeywordAutocomplete.createOption(for: "2008", tree: tree) == "2008")
    }

    @Test func notOfferedWhenTheExactPathExists() {
        let tree = makeTree([["JAHRE", "2008"], ["2008"]])
        #expect(KeywordAutocomplete.createOption(for: "2008", tree: tree) == nil)
        #expect(KeywordAutocomplete.createOption(for: "jahre > 2008", tree: tree) == nil)
    }

    @Test func offersMissingNestedPathsAndNormalizes() {
        let tree = makeTree([["PRIVAT", "PORTRAIT"]])
        #expect(
            KeywordAutocomplete.createOption(for: "strasse > portrait", tree: tree)
                == "STRASSE > PORTRAIT"
        )
        #expect(KeywordAutocomplete.createOption(for: "  ", tree: tree) == nil)
    }
}

/// U35: lifting a nested keyword to a group's top level, with the merge
/// semantics for name collisions.
@Suite struct KeywordMoveTests {
    @Test func movesNestedKeywordToTopLevelOfGroup() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let jahre = try KeywordDAO.ensurePath(["JAHRE", "2008"], groupId: nil, in: db)
            let group = try KeywordDAO.createGroup(name: "YEAR2", color: "#FFAA00", in: db)
            let survivor = try KeywordDAO.moveToTopLevel(jahre, groupId: group.id, in: db)
            let moved = try #require(try KeywordRecord.fetchOne(db, key: survivor))
            #expect(moved.name == "2008")
            #expect(moved.parentId == nil)
            #expect(moved.groupId == group.id)
            // The old parent stays (now childless) for the user to delete.
            let parent = try KeywordRecord.filter(Column("name") == "JAHRE").fetchOne(db)
            #expect(parent != nil)
        }
    }

    @Test func subtreeMovesAlong() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            _ = try KeywordDAO.ensurePath(["A", "B", "C"], groupId: nil, in: db)
            let b = try #require(try KeywordRecord.filter(Column("name") == "B").fetchOne(db)?.id)
            let survivor = try KeywordDAO.moveToTopLevel(b, groupId: nil, in: db)
            #expect(survivor == b)
            let c = try #require(try KeywordRecord.filter(Column("name") == "C").fetchOne(db))
            #expect(c.parentId == b)
        }
    }

    @Test func sameNamedTopLevelKeywordAbsorbsTheMovedOne() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            let p1 = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/m1.jpg")
            let p2 = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/m2.jpg")
            // Existing top-level 2008 (carried by p1) and JAHRE > 2008 (by p2).
            let existing = try KeywordDAO.ensurePath(["2008"], groupId: nil, in: db)
            try PhotoDAO.assignKeyword(existing, toPhotoIds: [p1], in: db)
            let nested = try KeywordDAO.ensurePath(["JAHRE", "2008"], groupId: nil, in: db)
            try PhotoDAO.assignKeyword(nested, toPhotoIds: [p2], in: db)
            let group = try KeywordDAO.createGroup(name: "YEAR2", color: "#FFAA00", in: db)

            let survivor = try KeywordDAO.moveToTopLevel(nested, groupId: group.id, in: db)
            #expect(survivor == existing)
            // The nested node is gone; the survivor carries BOTH photos.
            #expect(try KeywordRecord.fetchOne(db, key: nested) == nil)
            let carriers = try Int64.fetchAll(
                db, sql: "SELECT photoId FROM photoKeyword WHERE keywordId = ? ORDER BY photoId",
                arguments: [survivor]
            )
            #expect(carriers == [p1, p2])
            #expect(try KeywordRecord.fetchOne(db, key: survivor)?.groupId == group.id)
        }
    }

    @Test func mergeRecursesIntoSameNamedChildren() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            let photo = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/m3.jpg")
            // Top-level TRIP with child ROME; moving TRAVEL > TRIP (whose ROME
            // carries a photo, plus a unique PARIS) must fold both levels.
            _ = try KeywordDAO.ensurePath(["TRIP", "ROME"], groupId: nil, in: db)
            let sourceRome = try KeywordDAO.ensurePath(["TRAVEL", "TRIP", "ROME"], groupId: nil, in: db)
            _ = try KeywordDAO.ensurePath(["TRAVEL", "TRIP", "PARIS"], groupId: nil, in: db)
            try PhotoDAO.assignKeyword(sourceRome, toPhotoIds: [photo], in: db)
            let sourceTrip = try #require(
                try Int64.fetchOne(
                    db,
                    sql: """
                        SELECT k.id FROM keyword k
                        JOIN keyword p ON k.parentId = p.id
                        WHERE k.name = 'TRIP' AND p.name = 'TRAVEL'
                        """
                )
            )

            _ = try KeywordDAO.moveToTopLevel(sourceTrip, groupId: nil, in: db)

            // One TRIP, one ROME (under it, carrying the photo), PARIS re-hung.
            #expect(try KeywordRecord.filter(Column("name") == "TRIP").fetchCount(db) == 1)
            let trip = try #require(try KeywordRecord.filter(Column("name") == "TRIP").fetchOne(db))
            #expect(trip.parentId == nil)
            let rome = try #require(try KeywordRecord.filter(Column("name") == "ROME").fetchOne(db))
            #expect(rome.parentId == trip.id)
            let romeCarriers = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM photoKeyword WHERE keywordId = ?",
                arguments: [rome.id]
            )
            #expect(romeCarriers == 1)
            let paris = try #require(try KeywordRecord.filter(Column("name") == "PARIS").fetchOne(db))
            #expect(paris.parentId == trip.id)
        }
    }
}

/// U40: the rename-collision merge — renaming "_STRASSE" next to an
/// existing sibling "STRASSE" folds it into the sibling instead of failing.
@Suite struct KeywordMergeTests {
    @Test func siblingAbsorbsSourceAssignmentsAndChildren() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            let p1 = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/g1.jpg")
            let p2 = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/g2.jpg")
            // META > STRASSE (p1, child ALT) and META > _STRASSE (p2, both
            // a colliding ALT and a unique NEU below it).
            let target = try KeywordDAO.ensurePath(["META", "STRASSE"], groupId: nil, in: db)
            let targetAlt = try KeywordDAO.ensurePath(["META", "STRASSE", "ALT"], groupId: nil, in: db)
            let source = try KeywordDAO.ensurePath(["META", "_STRASSE"], groupId: nil, in: db)
            let sourceAlt = try KeywordDAO.ensurePath(["META", "_STRASSE", "ALT"], groupId: nil, in: db)
            _ = try KeywordDAO.ensurePath(["META", "_STRASSE", "NEU"], groupId: nil, in: db)
            try PhotoDAO.assignKeyword(target, toPhotoIds: [p1], in: db)
            try PhotoDAO.assignKeyword(source, toPhotoIds: [p2], in: db)
            try PhotoDAO.assignKeyword(sourceAlt, toPhotoIds: [p2], in: db)

            try KeywordDAO.merge(source, into: target, in: db)

            // Source subtree is gone; the survivor carries BOTH photos.
            #expect(try KeywordRecord.fetchOne(db, key: source) == nil)
            #expect(try KeywordRecord.fetchOne(db, key: sourceAlt) == nil)
            let carriers = try Int64.fetchAll(
                db, sql: "SELECT photoId FROM photoKeyword WHERE keywordId = ? ORDER BY photoId",
                arguments: [target]
            )
            #expect(carriers == [p1, p2])
            // ALT merged into the target's ALT (p2's assignment moved along);
            // NEU re-hung under the survivor.
            #expect(try KeywordRecord.filter(Column("name") == "ALT").fetchCount(db) == 1)
            let altCarriers = try Int64.fetchAll(
                db, sql: "SELECT photoId FROM photoKeyword WHERE keywordId = ?",
                arguments: [targetAlt]
            )
            #expect(altCarriers == [p2])
            let neu = try #require(try KeywordRecord.filter(Column("name") == "NEU").fetchOne(db))
            #expect(neu.parentId == target)
        }
    }

    @Test func mergingIntoItselfIsANoOp() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let id = try KeywordDAO.ensurePath(["STRASSE"], groupId: nil, in: db)
            try KeywordDAO.merge(id, into: id, in: db)
            #expect(try KeywordRecord.fetchOne(db, key: id) != nil)
        }
    }

    @Test func refusesMergeIntoOwnDescendant() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let child = try KeywordDAO.ensurePath(["A", "B"], groupId: nil, in: db)
            let parent = try #require(try KeywordRecord.fetchOne(db, key: child)?.parentId)
            #expect(throws: KeywordDAOError.mergeTargetInsideSource) {
                try KeywordDAO.merge(parent, into: child, in: db)
            }
            // Nothing was touched.
            #expect(try KeywordRecord.fetchCount(db) == 2)
        }
    }
}
