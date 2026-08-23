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

    /// `CompiledRules` is the single rule implementation (the interpreter was
    /// folded into it); pin its §7.3 semantics on a table so a future edit
    /// cannot drift silently.
    @Test func compiledRulesSemanticsTable() {
        let photo = PhotoRecord(id: 1, folderId: 1, path: "/p/Strasse.jpg", rating: 3,
                                captureDate: Date(timeIntervalSince1970: 1_000),
                                dateAdded: Date(timeIntervalSince1970: 2_000), importBatchId: 7)
        let empty = PhotoRecord(id: 2, folderId: 1, path: "/p/beach.png", rating: 0,
                                captureDate: nil,
                                dateAdded: Date(timeIntervalSince1970: 9_000), importBatchId: nil)
        let facts = PhotoQueryFacts(keywordPaths: ["STRASSE", "PEOPLE > ANNA"], keywordGroupIds: [3])
        let table: [(CollectionRuleRecord, Bool, Bool)] = [
            (rule("keyword", "contains", "straße"), true, false),
            (rule("keyword", "equals", "people > anna"), true, false),
            (rule("keyword", "doesNotContain", "ANNA"), false, true),
            (rule("filename", "contains", "STRAS"), true, false),
            (rule("rating", "greaterThan", " 2 "), true, false),
            (rule("rating", "doesNotEqual", "abc"), false, false),
            (rule("keywordCount", "equals", "2"), true, false),
            (rule("keywordGroup", "contains", "3"), true, false),
            (rule("keywordGroup", "doesNotEqual", "3"), false, true),
            (rule("dateRange", "lessThan", "5000"), true, false),
            (rule("captureDate", "greaterThan", "500"), true, false),
            (rule("importBatch", "equals", "7"), true, false),
            (rule("rating", "unknownOp", "3"), false, false),
        ]
        for (singleRule, expectHit, expectEmpty) in table {
            let compiled = CompiledRules([singleRule], matchAll: true)
            #expect(compiled.matches(photo, facts: facts) == expectHit,
                    "\(singleRule.type)/\(singleRule.operation)/\(singleRule.value)")
            #expect(compiled.matches(empty, facts: PhotoQueryFacts()) == expectEmpty,
                    "empty: \(singleRule.type)/\(singleRule.operation)/\(singleRule.value)")
        }
        // Unknown types are skipped (D6): alone → matches nothing (only a
        // genuinely empty rule list matches everything, Q6).
        #expect(!CompiledRules([rule("unknownType", "equals", "x")], matchAll: true).matches(empty, facts: PhotoQueryFacts()))
        #expect(CompiledRules([], matchAll: true).matches(empty, facts: PhotoQueryFacts()))
        // QueryEngine is a one-shot wrapper with identical results.
        #expect(QueryEngine.matches(photo, facts: facts, rules: table.map(\.0), matchAll: false))
        #expect(!QueryEngine.matches(empty, facts: PhotoQueryFacts(), rules: table.map(\.0), matchAll: true))
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
