import Testing
@testable import BallastCore

// MARK: - Keyword-tree counts + keyword filter (U29)

struct KeywordCountsTests {
    /// PEOPLE(1, group 100) > ANNA(2), PEOPLE > BOB(3), PLACES(4) > BERLIN(5)
    /// — PLACES has no group (UNGROUPED bucket).
    private var tree: KeywordTree {
        KeywordTree(records: [
            KeywordRecord(id: 1, groupId: 100, name: "PEOPLE"),
            KeywordRecord(id: 2, parentId: 1, name: "ANNA"),
            KeywordRecord(id: 3, parentId: 1, name: "BOB"),
            KeywordRecord(id: 4, name: "PLACES"),
            KeywordRecord(id: 5, parentId: 4, name: "BERLIN"),
        ])
    }

    @Test func countsRollUpSubtreesAndDeduplicatePerPhoto() {
        let counts = KeywordCounts.compute(
            keywordIdsByPhoto: [
                10: [2],        // ANNA → counts for ANNA and PEOPLE
                11: [2, 3],     // ANNA + BOB → PEOPLE counts ONCE
                12: [1],        // PEOPLE directly
                13: [5],        // BERLIN → counts for BERLIN and PLACES
                14: [],         // no keywords
            ],
            tree: tree
        )
        #expect(counts.byKeyword[1] == 3)  // photos 10, 11, 12
        #expect(counts.byKeyword[2] == 2)  // photos 10, 11
        #expect(counts.byKeyword[3] == 1)  // photo 11
        #expect(counts.byKeyword[4] == 1)  // photo 13
        #expect(counts.byKeyword[5] == 1)  // photo 13
        // Group rollup: ANNA/BOB inherit PEOPLE's group; PLACES/BERLIN are
        // ungrouped.
        #expect(counts.byGroup[100] == 3)  // photos 10, 11, 12
        #expect(counts.byGroup[KeywordCounts.ungroupedKey] == 1)  // photo 13
    }

    @Test func staleAssignmentIdsAreSkipped() {
        let counts = KeywordCounts.compute(
            keywordIdsByPhoto: [10: [99], 11: [2, 99]],
            tree: tree
        )
        #expect(counts.byKeyword[99] == nil)
        #expect(counts.byKeyword[2] == 1)
        #expect(counts.byKeyword[1] == 1)
        // The stale id contributes to no group — not even UNGROUPED.
        #expect(counts.byGroup[KeywordCounts.ungroupedKey] == nil)
        #expect(counts.byGroup[100] == 1)
    }

    @Test func emptyInputsYieldEmptyCounts() {
        #expect(KeywordCounts.compute(keywordIdsByPhoto: [:], tree: tree) == KeywordCounts.Result())
        #expect(KeywordCounts.compute(
            keywordIdsByPhoto: [1: [1]], tree: KeywordTree(records: [])
        ) == KeywordCounts.Result())
    }

    @Test func keywordSidebarItemFiltersBySubtreeMembership() {
        let subtree: Set<Int64> = [1, 2, 3]  // PEOPLE + children
        func matches(_ ids: Set<Int64>) -> Bool {
            SidebarFilter.matches(
                photo(),
                facts: PhotoQueryFacts(keywordIds: ids),
                item: .keyword(1),
                compiledCollections: [:],
                lastImportBatchId: nil,
                activeKeywordSubtree: subtree
            )
        }
        #expect(matches([2]))         // child hits the parent filter
        #expect(matches([1, 5]))      // direct hit
        #expect(!matches([5]))        // other branch
        #expect(!matches([]))         // no keywords
    }

    @Test func keywordItemCodecRoundTrips() {
        #expect(SidebarItem(encoded: SidebarItem.keyword(7).encoded) == .keyword(7))
        #expect(SidebarItem(encoded: "keyword:abc") == nil)
    }

    private func photo() -> PhotoRecord {
        PhotoRecord(id: 1, folderId: 1, path: "/x/x.jpg")
    }
}
