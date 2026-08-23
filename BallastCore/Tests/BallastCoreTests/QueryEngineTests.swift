import Foundation
import Testing
@testable import BallastCore

private func rule(_ type: String, _ op: String, _ value: String) -> CollectionRuleRecord {
    CollectionRuleRecord(collectionId: 1, type: type, operation: op, value: value, sortOrder: 0)
}

private func photo(
    _ id: Int64 = 1, filename: String = "IMG_0042.JPG", rating: Int = 0,
    added: TimeInterval = 1000, captured: TimeInterval? = nil, batch: Int64? = nil
) -> PhotoRecord {
    var record = PhotoRecord(
        folderId: 1,
        path: "/photos/\(filename)",
        rating: rating,
        captureDate: captured.map { Date(timeIntervalSince1970: $0) },
        dateAdded: Date(timeIntervalSince1970: added),
        importBatchId: batch
    )
    record.id = id
    return record
}

@Suite struct QueryEngineMatrixTests {
    /// Facts for a photo tagged PEOPLE > ANNA (group 7) and TRIP (ungrouped).
    let facts = PhotoQueryFacts(
        keywordPaths: ["PEOPLE > ANNA", "TRIP"],
        keywordGroupIds: [7]
    )

    private func matches(_ r: CollectionRuleRecord, _ p: PhotoRecord, _ f: PhotoQueryFacts? = nil) -> Bool {
        QueryEngine.matches(p, facts: f ?? facts, rules: [r], matchAll: true)
    }

    /// The complete §7.3 contract, table-driven: (type, op, value, expected).
    @Test func ruleMatrix() {
        let subject = photo(rating: 3, added: 1000, captured: 500, batch: 42)
        let cases: [(String, String, String, Bool)] = [
            // keyword — case-insensitive, over resolved paths; any-match.
            ("keyword", "contains", "anna", true),
            ("keyword", "contains", "people", true),
            ("keyword", "contains", "bob", false),
            ("keyword", "equals", "people > anna", true),
            ("keyword", "equals", "anna", false),
            ("keyword", "doesNotContain", "bob", true),
            ("keyword", "doesNotContain", "trip", false),
            ("keyword", "doesNotEqual", "trip", false),
            ("keyword", "doesNotEqual", "bob", true),
            ("keyword", "greaterThan", "a", false),
            ("keyword", "lessThan", "z", false),
            // rating — strict comparisons; doesNotEqual per U10; non-numeric no match.
            ("rating", "equals", "3", true),
            ("rating", "equals", "4", false),
            ("rating", "greaterThan", "2", true),
            ("rating", "greaterThan", "3", false),
            ("rating", "lessThan", "4", true),
            ("rating", "doesNotEqual", "4", true),
            ("rating", "doesNotEqual", "3", false),
            ("rating", "equals", "three", false),
            ("rating", "contains", "3", false),
            // filename — last path component incl. extension, case-insensitive.
            ("filename", "contains", "img_", true),
            ("filename", "contains", ".jpg", true),
            ("filename", "contains", "photos", false),
            ("filename", "equals", "img_0042.jpg", true),
            ("filename", "doesNotContain", "raw", true),
            ("filename", "doesNotEqual", "img_0042.jpg", false),
            ("filename", "greaterThan", "a", false),
            // keywordCount — enables "untagged" as equals 0.
            ("keywordCount", "equals", "2", true),
            ("keywordCount", "equals", "0", false),
            ("keywordCount", "greaterThan", "1", true),
            ("keywordCount", "lessThan", "3", true),
            ("keywordCount", "doesNotEqual", "0", true),
            // keywordGroup — inverted-by-exception operator handling.
            ("keywordGroup", "contains", "7", true),
            ("keywordGroup", "equals", "7", true),
            ("keywordGroup", "greaterThan", "7", true),
            ("keywordGroup", "lessThan", "7", true),
            ("keywordGroup", "doesNotContain", "7", false),
            ("keywordGroup", "doesNotEqual", "7", false),
            ("keywordGroup", "contains", "9", false),
            ("keywordGroup", "doesNotContain", "9", true),
            ("keywordGroup", "contains", "PEOPLE", false),
            // dateRange — import time, ordering only.
            ("dateRange", "greaterThan", "999", true),
            ("dateRange", "greaterThan", "1000", false),
            ("dateRange", "lessThan", "1001", true),
            ("dateRange", "equals", "1000", false),
            ("dateRange", "greaterThan", "yesterday", false),
            // captureDate (U10) — EXIF time, ordering only.
            ("captureDate", "greaterThan", "499", true),
            ("captureDate", "lessThan", "499", false),
            ("captureDate", "lessThan", "501", true),
            // importBatch — operator ignored.
            ("importBatch", "equals", "42", true),
            ("importBatch", "greaterThan", "42", true),
            ("importBatch", "equals", "41", false),
        ]
        for (type, op, value, expected) in cases {
            #expect(
                matches(rule(type, op, value), subject) == expected,
                "\(type) \(op) '\(value)' should be \(expected)"
            )
        }
    }

    @Test func captureDateNeverMatchesUndatedPhotos() {
        let undated = photo(captured: nil)
        #expect(!matches(rule("captureDate", "greaterThan", "0"), undated))
        #expect(!matches(rule("captureDate", "lessThan", "9999999999"), undated))
    }

    @Test func emptyRuleListMatchesEverything() {
        #expect(QueryEngine.matches(photo(), facts: facts, rules: [], matchAll: true))
        #expect(QueryEngine.matches(photo(), facts: facts, rules: [], matchAll: false))
    }

    @Test func unknownRuleTypesAreSkippedNotFailed() {
        // D6: a newer app version's rule type must not break evaluation.
        let unknown = rule("faceCount", "equals", "2")
        let known = rule("rating", "equals", "3")
        let subject = photo(rating: 3)
        #expect(QueryEngine.matches(subject, facts: facts, rules: [unknown, known], matchAll: true))
        // All rules unknown → the collection matches NOTHING (D6); only a
        // genuinely empty rule list matches everything (Q6).
        #expect(!QueryEngine.matches(subject, facts: facts, rules: [unknown], matchAll: true))
        #expect(!QueryEngine.matches(subject, facts: facts, rules: [unknown], matchAll: false))
        // Unknown *operator* on a known type is false, not skipped (§7.3).
        #expect(!QueryEngine.matches(subject, facts: facts, rules: [rule("rating", "matchesRegex", "3")], matchAll: true))
    }

    /// An empty (after trimming) value is "rule not configured yet": it
    /// constrains nothing, whatever the type or operator.
    @Test func emptyValueMatchesEverythingForEveryRuleType() {
        let subject = photo(rating: 3, added: 1000, captured: 500, batch: 42)
        let ops = ["contains", "equals", "doesNotContain", "doesNotEqual", "greaterThan", "lessThan", "bogus"]
        for type in RuleType.allCases {
            for op in ops {
                for value in ["", "   ", "\t\n"] {
                    #expect(matches(rule(type.rawValue, op, value), subject), "\(type) \(op) '\(value)'")
                    #expect(matches(rule(type.rawValue, op, value), photo(rating: 0), PhotoQueryFacts()), "\(type) \(op)")
                }
            }
        }
        // …but an empty value does not rescue a rule whose type is unknown.
        #expect(!QueryEngine.matches(subject, facts: facts, rules: [rule("faceCount", "equals", "")], matchAll: true))
    }

    @Test func valuesAreTrimmedBeforeFolding() {
        let subject = photo(filename: "IMG_0042.JPG", rating: 3)
        #expect(matches(rule("keyword", "contains", "  Anna "), subject))
        #expect(matches(rule("keyword", "equals", " people > anna\n"), subject))
        #expect(matches(rule("filename", "equals", "  img_0042.jpg "), subject))
        #expect(matches(rule("filename", "contains", " 0042 "), subject))
        #expect(!matches(rule("keyword", "doesNotContain", " anna "), subject))
    }

    @Test func importBatchIgnoresOperatorEvenWhenUnknown() {
        let subject = photo(batch: 42)
        #expect(matches(rule("importBatch", "matchesRegex", "42"), subject))
        #expect(matches(rule("importBatch", "", "42"), subject))
        #expect(!matches(rule("importBatch", "", "41"), subject))
        #expect(!matches(rule("importBatch", "equals", "forty-two"), subject))
    }

    @Test func matchAllVersusMatchAny() {
        let subject = photo(rating: 3)
        let hit = rule("rating", "equals", "3")
        let miss = rule("rating", "equals", "5")
        #expect(!QueryEngine.matches(subject, facts: facts, rules: [hit, miss], matchAll: true))
        #expect(QueryEngine.matches(subject, facts: facts, rules: [hit, miss], matchAll: false))
    }

    /// C2 acceptance: a group rule matches photos tagged with a *nested*
    /// keyword whose root carries the group.
    @Test func groupRuleMatchesNestedKeywordsViaTreeFacts() {
        var people = KeywordRecord(parentId: nil, groupId: 7, name: "PEOPLE")
        people.id = 1
        // Child created without its own group — group comes from the ancestor.
        var anna = KeywordRecord(parentId: 1, groupId: nil, name: "ANNA")
        anna.id = 2
        let tree = KeywordTree(records: [people, anna])
        #expect(tree.effectiveGroupId(of: 2) == 7)

        let nestedFacts = PhotoQueryFacts(
            keywordPaths: [tree.path(of: 2)],
            keywordGroupIds: Set([tree.effectiveGroupId(of: 2)].compactMap(\.self))
        )
        #expect(nestedFacts.keywordPaths == ["PEOPLE > ANNA"])
        #expect(matches(rule("keywordGroup", "contains", "7"), photo(), nestedFacts))
        #expect(!matches(rule("keywordGroup", "contains", "8"), photo(), nestedFacts))
    }
}

@Suite struct SidebarItemTests {
    @Test func codecRoundTripsAllCases() {
        let items: [SidebarItem] = [.allPhotos, .lastImport, .rating(1), .rating(5), .collection(12)]
        for item in items {
            #expect(SidebarItem(encoded: item.encoded) == item)
        }
        #expect(SidebarItem(encoded: "rating:0") == nil)
        #expect(SidebarItem(encoded: "rating:6") == nil)
        #expect(SidebarItem(encoded: "collection:abc") == nil)
        #expect(SidebarItem(encoded: "garbage") == nil)
    }

    @Test func lastImportBeforeAnyImportMatchesNothing() {
        // Q8: the list is empty, not full.
        let subject = photo(batch: nil)
        #expect(!SidebarFilter.matches(
            subject, facts: PhotoQueryFacts(), item: .lastImport,
            compiledCollections: [:], lastImportBatchId: nil
        ))
        let batched = photo(batch: 9)
        #expect(SidebarFilter.matches(
            batched, facts: PhotoQueryFacts(), item: .lastImport,
            compiledCollections: [:], lastImportBatchId: 9
        ))
    }

    @Test func ratingRowsAreExactMatches() {
        // Q9: ★★★ means exactly three.
        let threeStars = photo(rating: 3)
        #expect(SidebarFilter.matches(
            threeStars, facts: PhotoQueryFacts(), item: .rating(3),
            compiledCollections: [:], lastImportBatchId: nil
        ))
        let fourStars = photo(rating: 4)
        #expect(!SidebarFilter.matches(
            fourStars, facts: PhotoQueryFacts(), item: .rating(3),
            compiledCollections: [:], lastImportBatchId: nil
        ))
    }

    @Test func deletedCollectionMatchesNothing() {
        #expect(!SidebarFilter.matches(
            photo(), facts: PhotoQueryFacts(), item: .collection(99),
            compiledCollections: [:], lastImportBatchId: nil
        ))
    }
}
