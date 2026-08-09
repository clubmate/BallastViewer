import Foundation
import Testing
@testable import BallastCore

/// Guards for the 2026-08 performance pass: the compiled rule evaluator must
/// agree with the interpreter, and the memoized tree lookups must agree with
/// the walking implementations.
@Suite struct PerfOptimizationTests {
    private func rule(_ type: String, _ op: String, _ value: String) -> CollectionRuleRecord {
        CollectionRuleRecord(collectionId: 1, type: type, operation: op, value: value, sortOrder: 0)
    }

    @Test func compiledRulesAgreeWithInterpreter() {
        let photos = [
            PhotoRecord(id: 1, folderId: 1, path: "/p/Strasse.jpg", rating: 3,
                        captureDate: Date(timeIntervalSince1970: 1_000),
                        dateAdded: Date(timeIntervalSince1970: 2_000), importBatchId: 7),
            PhotoRecord(id: 2, folderId: 1, path: "/p/beach.png", rating: 0,
                        captureDate: nil,
                        dateAdded: Date(timeIntervalSince1970: 9_000), importBatchId: nil),
        ]
        let facts = [
            PhotoQueryFacts(keywordPaths: ["STRASSE", "PEOPLE > ANNA"], keywordGroupIds: [3]),
            PhotoQueryFacts(),
        ]
        let rules = [
            rule("keyword", "contains", "straße"),
            rule("keyword", "equals", "people > anna"),
            rule("keyword", "doesNotContain", "ANNA"),
            rule("filename", "contains", "STRAS"),
            rule("rating", "greaterThan", " 2 "),
            rule("rating", "doesNotEqual", "abc"),
            rule("keywordCount", "equals", "2"),
            rule("keywordGroup", "contains", "3"),
            rule("keywordGroup", "doesNotEqual", "3"),
            rule("dateRange", "lessThan", "5000"),
            rule("captureDate", "greaterThan", "500"),
            rule("importBatch", "equals", "7"),
            rule("unknownType", "equals", "x"),
            rule("rating", "unknownOp", "3"),
        ]
        for (photo, fact) in zip(photos, facts) {
            for singleRule in rules {
                for matchAll in [true, false] {
                    let interpreted = QueryEngine.matches(
                        photo, facts: fact, rules: [singleRule], matchAll: matchAll
                    )
                    let compiled = CompiledRules([singleRule], matchAll: matchAll)
                        .matches(photo, facts: fact)
                    #expect(
                        interpreted == compiled,
                        "divergence: \(singleRule.type)/\(singleRule.operation)/\(singleRule.value) matchAll=\(matchAll) photo=\(photo.id ?? 0)"
                    )
                }
            }
            // Whole-set semantics: empty and mixed lists.
            #expect(
                QueryEngine.matches(photo, facts: fact, rules: [], matchAll: true)
                    == CompiledRules([], matchAll: true).matches(photo, facts: fact)
            )
            #expect(
                QueryEngine.matches(photo, facts: fact, rules: rules, matchAll: false)
                    == CompiledRules(rules, matchAll: false).matches(photo, facts: fact)
            )
        }
    }

    @Test func memoizedTreeLookupsAgreeWithWalks() {
        let tree = KeywordTree(records: [
            KeywordRecord(id: 1, parentId: nil, groupId: 10, name: "PEOPLE"),
            KeywordRecord(id: 2, parentId: 1, groupId: nil, name: "TEAM"),
            KeywordRecord(id: 3, parentId: 2, groupId: nil, name: "ANNA"),
            KeywordRecord(id: 4, parentId: nil, groupId: nil, name: "STRASSE"),
        ])
        #expect(tree.path(of: 3) == "PEOPLE > TEAM > ANNA")
        #expect(tree.path(of: 3) == tree.pathComponents(of: 3).joined(separator: KeywordTree.separator))
        #expect(tree.effectiveGroupId(of: 3) == 10)
        #expect(tree.effectiveGroupId(of: 4) == nil)
        #expect(tree.foldedPath(of: 4) == CaseInsensitiveMatch.fold("STRASSE"))

        // Autocomplete over the folded corpus behaves like the ICU search.
        #expect(KeywordAutocomplete.suggestions(for: "straße", tree: tree) == ["STRASSE"])
        #expect(KeywordAutocomplete.suggestions(for: "anna", tree: tree) == ["PEOPLE > TEAM > ANNA"])
    }

    @Test func treeDeltaDerivationsMatchFullRebuild() {
        let base = KeywordTree(records: [
            KeywordRecord(id: 1, parentId: nil, groupId: 10, name: "PEOPLE"),
            KeywordRecord(id: 2, parentId: 1, groupId: nil, name: "ANNA"),
        ])
        let inserted = base.inserting(KeywordRecord(id: 3, parentId: 1, groupId: nil, name: "BOB"))
        #expect(inserted.path(of: 3) == "PEOPLE > BOB")
        #expect(inserted.count == 3)

        let renamed = base.renaming(1, to: "FRIENDS")
        #expect(renamed.path(of: 2) == "FRIENDS > ANNA")

        let deleted = base.deletingSubtree(1)
        #expect(deleted.isEmpty)

        let ungrouped = base.removingGroup(10)
        #expect(ungrouped.effectiveGroupId(of: 2) == nil)
        #expect(ungrouped.node(1)?.groupId == nil)
    }
}
