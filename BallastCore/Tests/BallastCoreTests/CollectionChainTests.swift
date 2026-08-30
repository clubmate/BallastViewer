import Foundation
import GRDB
import Testing
@testable import BallastCore

/// U41: child Smart Collections — a child's result is the parent's result AND
/// its own rules, evaluated as a compiled chain.
@Suite struct CollectionChainTests {
    private func photo(_ id: Int64, rating: Int = 0) -> PhotoRecord {
        var record = PhotoRecord(folderId: 1, path: "/p/\(id).jpg", rating: rating)
        record.id = id
        return record
    }

    private func collection(
        _ id: Int64, parentId: Int64? = nil, matchAll: Bool = true
    ) -> SmartCollectionRecord {
        var record = SmartCollectionRecord(
            groupId: 1, parentId: parentId, name: "C\(id)", matchAll: matchAll, sortOrder: 0
        )
        record.id = id
        return record
    }

    private func rule(_ collectionId: Int64, _ type: String, _ op: String, _ value: String) -> CollectionRuleRecord {
        CollectionRuleRecord(collectionId: collectionId, type: type, operation: op, value: value, sortOrder: 0)
    }

    @Test func childAndsParentRulesOntoItsOwn() {
        // Parent: keyword contains STRASSE. Child: keyword contains 2012.
        let chains = CompiledRuleChain.chains(
            collections: [collection(1), collection(2, parentId: 1)],
            rulesByCollection: [
                1: [rule(1, "keyword", "contains", "STRASSE")],
                2: [rule(2, "keyword", "contains", "2012")],
            ]
        )
        let both = PhotoQueryFacts(keywordPaths: ["META > STRASSE", "2012"])
        let onlyParent = PhotoQueryFacts(keywordPaths: ["META > STRASSE"])
        let onlyChild = PhotoQueryFacts(keywordPaths: ["2012"])
        let subject = photo(1)
        #expect(chains[2]!.matches(subject, facts: both))
        #expect(!chains[2]!.matches(subject, facts: onlyParent))
        #expect(!chains[2]!.matches(subject, facts: onlyChild))
        // The parent itself is untouched by having children.
        #expect(chains[1]!.matches(subject, facts: onlyParent))
    }

    @Test func everyLevelKeepsItsOwnMatchMode() {
        // OR parent (PARIS or ROME), AND grandchild via AND child: three levels.
        let chains = CompiledRuleChain.chains(
            collections: [
                collection(1, matchAll: false),
                collection(2, parentId: 1),
                collection(3, parentId: 2),
            ],
            rulesByCollection: [
                1: [rule(1, "keyword", "equals", "PARIS"), rule(1, "keyword", "equals", "ROME")],
                2: [rule(2, "rating", "greaterThan", "2")],
                3: [rule(3, "keyword", "contains", "2012")],
            ]
        )
        let subject = photo(1, rating: 4)
        #expect(chains[3]!.matches(subject, facts: PhotoQueryFacts(keywordPaths: ["ROME", "2012"])))
        #expect(!chains[3]!.matches(subject, facts: PhotoQueryFacts(keywordPaths: ["ROME"])))
        #expect(!chains[3]!.matches(
            photo(2, rating: 1), facts: PhotoQueryFacts(keywordPaths: ["ROME", "2012"])
        ))
        #expect(!chains[3]!.matches(subject, facts: PhotoQueryFacts(keywordPaths: ["2012"])))
    }

    /// A child with no own rules shows exactly the parent's result (Q6 + U41).
    @Test func ruleLessChildEqualsParent() {
        let chains = CompiledRuleChain.chains(
            collections: [collection(1), collection(2, parentId: 1)],
            rulesByCollection: [1: [rule(1, "rating", "equals", "5")]]
        )
        #expect(chains[2]!.matches(photo(1, rating: 5), facts: PhotoQueryFacts()))
        #expect(!chains[2]!.matches(photo(2, rating: 4), facts: PhotoQueryFacts()))
    }

    /// A hand-edited cycle must terminate, not hang; a dangling parent id
    /// ends the walk.
    @Test func cyclesAndDanglingParentsAreCut() {
        let chains = CompiledRuleChain.chains(
            collections: [
                collection(1, parentId: 2),
                collection(2, parentId: 1),
                collection(3, parentId: 99),
            ],
            rulesByCollection: [3: [rule(3, "rating", "equals", "1")]]
        )
        #expect(chains.count == 3)
        #expect(chains[3]!.matches(photo(1, rating: 1), facts: PhotoQueryFacts()))
    }

    @Test func hierarchyLookups() {
        let collections = [
            collection(1), collection(2, parentId: 1), collection(3, parentId: 2),
            collection(4, parentId: 1), collection(5),
        ]
        #expect(CollectionHierarchy.descendantIds(of: 1, in: collections) == [2, 3, 4])
        #expect(CollectionHierarchy.descendantIds(of: 5, in: collections).isEmpty)
        #expect(CollectionHierarchy.ancestors(of: 3, in: collections).map(\.id) == [2, 1])
        #expect(CollectionHierarchy.ancestors(of: 5, in: collections).isEmpty)
    }

    @Test func countsStoreCountsChildrenThroughTheChain() {
        var store = CollectionCountsStore()
        let photos = [photo(1, rating: 5), photo(2, rating: 5), photo(3, rating: 1)]
        // Parent: rating > 0 (3 photos); child: rating equals 5 (2 photos).
        store.rebuild(
            photos: photos,
            collections: [collection(10), collection(11, parentId: 10)],
            rulesByCollection: [
                10: [rule(10, "rating", "greaterThan", "0")],
                11: [rule(11, "rating", "equals", "5")],
            ],
            lastImportBatchId: nil,
            facts: { _ in PhotoQueryFacts() }
        )
        #expect(store.counts.collections[10] == 3)
        #expect(store.counts.collections[11] == 2)
    }

    /// v6 migration: deleting a parent cascades through the child subtree,
    /// rules included.
    @Test func deletingAParentCascadesThroughTheSubtree() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let group = try CollectionDAO.createGroup(name: "G", in: db)
            let parent = try CollectionDAO.createCollection(name: "STRASSE", inGroup: group.id!, in: db)
            let child = try CollectionDAO.createCollection(
                name: "2012", inGroup: group.id!, parentId: parent.id, in: db
            )
            let grandchild = try CollectionDAO.createCollection(
                name: "SOMMER", inGroup: group.id!, parentId: child.id, in: db
            )
            try CollectionDAO.saveRules(
                [(type: "keyword", operation: "contains", value: "2012")],
                forCollection: child.id!, in: db
            )
            try CollectionDAO.deleteCollection(parent.id!, in: db)
            #expect(try SmartCollectionRecord.fetchCount(db) == 0)
            #expect(try CollectionRuleRecord.fetchCount(db) == 0)
            _ = grandchild
        }
    }
}
