import Foundation
import GRDB
import Testing
@testable import BallastCore

@Suite struct KeywordResolverTests {
    private func makeTree(_ paths: [[String]]) throws -> KeywordTree {
        let dbQueue = try makeTestDatabase()
        return try dbQueue.write { db in
            for path in paths {
                try KeywordDAO.ensurePath(path, groupId: nil, in: db)
            }
            return KeywordTree(records: try KeywordDAO.fetchAll(db))
        }
    }

    @Test func singleNameResolvesToFullPathFirstMatch() throws {
        // Q16 + the step-8 acceptance line: typing ANNA assigns PEOPLE > ANNA.
        let tree = try makeTree([["PEOPLE", "ANNA"], ["ZOO", "ANNA"]])
        let resolution = KeywordResolver.resolve("anna", tree: tree)
        let annaId = tree.find(pathComponents: ["PEOPLE", "ANNA"])!
        #expect(resolution == .existing(annaId))
        #expect(tree.path(of: annaId) == "PEOPLE > ANNA")
    }

    @Test func pathInputResolvesExactNode() throws {
        // Accepted autocomplete suggestions are full paths (Q17).
        let tree = try makeTree([["PEOPLE", "ANNA"], ["ZOO", "ANNA"]])
        let zooAnna = tree.find(pathComponents: ["ZOO", "ANNA"])!
        #expect(KeywordResolver.resolve("ZOO > ANNA", tree: tree) == .existing(zooAnna))
        #expect(KeywordResolver.resolve("zoo > anna", tree: tree) == .existing(zooAnna))
    }

    @Test func unmatchedTextBecomesUppercasedCreation() throws {
        let tree = try makeTree([["PEOPLE", "ANNA"]])
        #expect(KeywordResolver.resolve("  sunset ", tree: tree) == .create(["SUNSET"]))
        #expect(KeywordResolver.resolve("TRIPS > rome", tree: tree) == .create(["TRIPS", "ROME"]))
        #expect(KeywordResolver.resolve("   ", tree: tree) == nil)
        #expect(KeywordResolver.resolve(" > ", tree: tree) == nil)
    }
}

@Suite struct KeywordAutocompleteTests {
    @Test func offersEveryNodeFilteredCaseInsensitively() throws {
        // Q17: PEOPLE, PEOPLE > TEAM and PEOPLE > TEAM > ANNA are all offered.
        let dbQueue = try makeTestDatabase()
        let tree = try dbQueue.write { db in
            try KeywordDAO.ensurePath(["PEOPLE", "TEAM", "ANNA"], groupId: nil, in: db)
            try KeywordDAO.ensurePath(["ZEBRA"], groupId: nil, in: db)
            return KeywordTree(records: try KeywordDAO.fetchAll(db))
        }
        #expect(KeywordAutocomplete.suggestions(for: "te", tree: tree) == [
            "PEOPLE > TEAM", "PEOPLE > TEAM > ANNA",
        ])
        #expect(KeywordAutocomplete.suggestions(for: "anna", tree: tree) == [
            "PEOPLE > TEAM > ANNA",
        ])
        #expect(KeywordAutocomplete.suggestions(for: "", tree: tree).isEmpty)
    }

    @Test func highlightArrowSemantics() {
        // Spec §9.8 table: ↓ wraps; ↑ exits at the first entry, enters at the last.
        var highlight = AutocompleteHighlight()
        #expect(highlight.index == nil)

        highlight.moveDown(count: 3)
        #expect(highlight.index == 0)
        highlight.moveDown(count: 3)
        highlight.moveDown(count: 3)
        #expect(highlight.index == 2)
        highlight.moveDown(count: 3)
        #expect(highlight.index == 0) // wraps last → first

        highlight.moveUp(count: 3)
        #expect(highlight.index == nil) // first → no highlight
        highlight.moveUp(count: 3)
        #expect(highlight.index == 2) // no highlight → last

        highlight.reset()
        #expect(highlight.index == nil)

        highlight.moveDown(count: 0)
        #expect(highlight.index == nil)

        highlight.moveDown(count: 3)
        highlight.clamp(count: 3)
        #expect(highlight.index == 0)
        highlight.moveDown(count: 3)
        highlight.moveDown(count: 3)
        highlight.clamp(count: 1)
        #expect(highlight.index == 0)
        highlight.clamp(count: 0)
        #expect(highlight.index == nil)
    }
}

@Suite struct KeywordChipBuilderTests {
    @Test func intersectionNotUnion() {
        // Q14: only keywords common to every selected photo are shown.
        let byPhoto: [Int64: Set<Int64>] = [1: [10, 20], 2: [20, 30], 3: [20]]
        #expect(KeywordChipBuilder.commonKeywordIds(photoIds: [1, 2, 3], keywordIdsByPhoto: byPhoto) == [20])
        #expect(KeywordChipBuilder.commonKeywordIds(photoIds: [1], keywordIdsByPhoto: byPhoto) == [10, 20])
        #expect(KeywordChipBuilder.commonKeywordIds(photoIds: [1, 4], keywordIdsByPhoto: byPhoto).isEmpty)
        #expect(KeywordChipBuilder.commonKeywordIds(photoIds: [], keywordIdsByPhoto: byPhoto).isEmpty)
    }

    @Test func chipOrderIsGroupOrderThenAlphaUngroupedLast() throws {
        // Q18 + step-8 acceptance: group order, then alpha; ungrouped grey last.
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let people = try KeywordDAO.createGroup(name: "PEOPLE", color: "#BF5AF2", in: db)
            let year = try KeywordDAO.createGroup(name: "YEAR", color: "#007AFF", in: db)

            let anna = try KeywordDAO.ensurePath(["PEOPLE", "ANNA"], groupId: people.id, in: db)
            let bob = try KeywordDAO.ensurePath(["PEOPLE", "BOB"], groupId: people.id, in: db)
            let y2024 = try KeywordDAO.ensurePath(["2024"], groupId: year.id, in: db)
            let adhoc = try KeywordDAO.ensurePath(["SUNSET"], groupId: nil, in: db)

            let tree = KeywordTree(records: try KeywordDAO.fetchAll(db))
            let groups = try KeywordDAO.fetchGroups(db)

            let chips = KeywordChipBuilder.chips(
                forKeywordIds: [adhoc, y2024, bob, anna], tree: tree, groups: groups
            )
            #expect(chips.map(\.path) == ["PEOPLE > ANNA", "PEOPLE > BOB", "2024", "SUNSET"])
            #expect(chips.map(\.colorHex) == ["#BF5AF2", "#BF5AF2", "#007AFF", nil])

            // Nested chips inherit the nearest grouped ancestor's colour (C2)…
            let nested = try KeywordDAO.ensurePath(["PEOPLE", "ANNA", "PORTRAIT"], groupId: nil, in: db)
            let tree2 = KeywordTree(records: try KeywordDAO.fetchAll(db))
            let nestedChips = KeywordChipBuilder.chips(forKeywordIds: [nested], tree: tree2, groups: groups)
            #expect(nestedChips.first?.colorHex == "#BF5AF2")

            // …and group reorder reorders chips (Q18: order is semantic).
            try KeywordDAO.reorderGroups([year.id!, people.id!], in: db)
            let reordered = KeywordChipBuilder.chips(
                forKeywordIds: [y2024, anna], tree: tree2, groups: try KeywordDAO.fetchGroups(db)
            )
            #expect(reordered.map(\.path) == ["2024", "PEOPLE > ANNA"])
        }
    }
}
