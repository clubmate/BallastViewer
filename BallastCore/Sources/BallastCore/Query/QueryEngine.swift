import Foundation

/// The rule vocabulary (spec §7.3 plus the U10 `captureDate` addition). Types
/// and operators are stored as plain strings; whatever this enum does not
/// recognise is *skipped* by the engine (D6) so libraries written by newer app
/// versions still open.
public enum RuleType: String, CaseIterable, Sendable {
    case keyword
    case rating
    case filename
    case keywordCount
    case keywordGroup
    /// Compares `dateAdded` — import time, not capture time (spec §7.3).
    case dateRange
    /// U10: compares EXIF capture date; photos without one never match.
    case captureDate
    /// Used internally by LAST IMPORT; operator ignored (spec §7.3).
    case importBatch
}

public enum RuleOperator: String, CaseIterable, Sendable {
    case contains
    case equals
    case doesNotContain
    case doesNotEqual
    case greaterThan
    case lessThan
}

/// Per-photo facts the rules need beyond the record itself: the photo's
/// resolved keyword paths and the *effective* keyword groups (nearest grouped
/// ancestor — this is what makes group rules match nested keywords, fixing C2).
public struct PhotoQueryFacts: Equatable, Sendable {
    public var keywordPaths: [String]
    public var keywordGroupIds: Set<Int64>
    /// Case-folded twins of `keywordPaths` (same order) — supplied by
    /// `LibrarySnapshot.queryFacts` from the tree's memo so compiled rules
    /// match with plain `contains`. Empty means "not precomputed"; consumers
    /// fold on the fly then.
    public var foldedKeywordPaths: [String]

    public init(
        keywordPaths: [String] = [],
        keywordGroupIds: Set<Int64> = [],
        foldedKeywordPaths: [String] = []
    ) {
        self.keywordPaths = keywordPaths
        self.keywordGroupIds = keywordGroupIds
        self.foldedKeywordPaths = foldedKeywordPaths
    }
}

/// One collection's rules, parsed once: the hot paths (counts rebuild over the
/// whole catalog, the active-collection filter) evaluate every photo against
/// the same unchanged rules — enum parsing, value parsing, case folding and
/// the applicable-filter allocation all happen here instead of per photo.
/// Semantics mirror `QueryEngine.matches` exactly.
public struct CompiledRules: Sendable {
    struct Rule: Sendable {
        let type: RuleType
        /// nil = known type with unknown operator → evaluates false (§7.3).
        let op: RuleOperator?
        let value: String
        let foldedValue: String
        let intValue: Int?
        let dateValue: Date?
        let groupIdValue: Int64?
    }

    let rules: [Rule]
    public let matchAll: Bool

    public init(_ records: [CollectionRuleRecord], matchAll: Bool) {
        self.matchAll = matchAll
        // Unknown types are skipped entirely (D6), like the interpreter.
        rules = records.compactMap { record in
            guard let type = RuleType(rawValue: record.type) else { return nil }
            let trimmed = record.value.trimmingCharacters(in: .whitespaces)
            return Rule(
                type: type,
                op: RuleOperator(rawValue: record.operation),
                value: record.value,
                foldedValue: CaseInsensitiveMatch.fold(record.value),
                intValue: Int(trimmed),
                dateValue: Double(trimmed).map { Date(timeIntervalSince1970: $0) },
                groupIdValue: Int64(record.value)
            )
        }
    }

    /// Empty rule list matches everything (Q6).
    public func matches(_ photo: PhotoRecord, facts: PhotoQueryFacts) -> Bool {
        guard !rules.isEmpty else { return true }
        if matchAll {
            return rules.allSatisfy { evaluate($0, photo: photo, facts: facts) }
        }
        return rules.contains { evaluate($0, photo: photo, facts: facts) }
    }

    private func evaluate(_ rule: Rule, photo: PhotoRecord, facts: PhotoQueryFacts) -> Bool {
        guard let op = rule.op else { return false }
        switch rule.type {
        case .keyword:
            return Self.keywordSetRule(Self.foldedPaths(facts), op, rule.foldedValue)
        case .filename:
            return Self.foldedStringRule(
                CaseInsensitiveMatch.fold(photo.filename), op, rule.foldedValue
            )
        case .rating:
            return Self.intRule(photo.rating, op, rule.intValue)
        case .keywordCount:
            return Self.intRule(facts.keywordPaths.count, op, rule.intValue)
        case .keywordGroup:
            guard let groupId = rule.groupIdValue else { return false }
            let has = facts.keywordGroupIds.contains(groupId)
            return (op == .doesNotContain || op == .doesNotEqual) ? !has : has
        case .dateRange:
            return Self.dateRule(photo.dateAdded, op, rule.dateValue)
        case .captureDate:
            guard let captureDate = photo.captureDate else { return false }
            return Self.dateRule(captureDate, op, rule.dateValue)
        case .importBatch:
            return photo.importBatchId.map(String.init) == rule.value
        }
    }

    private static func foldedPaths(_ facts: PhotoQueryFacts) -> [String] {
        facts.foldedKeywordPaths.count == facts.keywordPaths.count
            ? facts.foldedKeywordPaths
            : facts.keywordPaths.map(CaseInsensitiveMatch.fold)
    }

    private static func keywordSetRule(_ folded: [String], _ op: RuleOperator, _ needle: String) -> Bool {
        switch op {
        case .contains: return folded.contains { $0.contains(needle) }
        case .equals: return folded.contains { $0 == needle }
        case .doesNotContain: return !folded.contains { $0.contains(needle) }
        case .doesNotEqual: return !folded.contains { $0 == needle }
        case .greaterThan, .lessThan: return false
        }
    }

    private static func foldedStringRule(_ haystack: String, _ op: RuleOperator, _ needle: String) -> Bool {
        switch op {
        case .contains: return haystack.contains(needle)
        case .equals: return haystack == needle
        case .doesNotContain: return !haystack.contains(needle)
        case .doesNotEqual: return haystack != needle
        case .greaterThan, .lessThan: return false
        }
    }

    private static func intRule(_ subject: Int, _ op: RuleOperator, _ number: Int?) -> Bool {
        guard let number else { return false }
        switch op {
        case .equals: return subject == number
        case .doesNotEqual: return subject != number
        case .greaterThan: return subject > number
        case .lessThan: return subject < number
        case .contains, .doesNotContain: return false
        }
    }

    private static func dateRule(_ subject: Date, _ op: RuleOperator, _ reference: Date?) -> Bool {
        guard let reference else { return false }
        switch op {
        case .greaterThan: return subject > reference
        case .lessThan: return subject < reference
        case .equals, .doesNotEqual, .contains, .doesNotContain: return false
        }
    }
}

/// Pure, stateless rule evaluation (spec §7.2/§7.3).
public enum QueryEngine {
    /// Empty rule list matches everything (Q6). Rules with an unknown *type*
    /// are skipped entirely (D6); a known type with an unsupported operator
    /// returns false per the §7.3 contract.
    public static func matches(
        _ photo: PhotoRecord,
        facts: PhotoQueryFacts,
        rules: [CollectionRuleRecord],
        matchAll: Bool
    ) -> Bool {
        let applicable = rules.filter { RuleType(rawValue: $0.type) != nil }
        guard !applicable.isEmpty else { return true }
        if matchAll {
            return applicable.allSatisfy { evaluate($0, photo: photo, facts: facts) }
        }
        return applicable.contains { evaluate($0, photo: photo, facts: facts) }
    }

    static func evaluate(
        _ rule: CollectionRuleRecord, photo: PhotoRecord, facts: PhotoQueryFacts
    ) -> Bool {
        guard let type = RuleType(rawValue: rule.type),
              let op = RuleOperator(rawValue: rule.operation)
        else { return false }

        switch type {
        case .keyword:
            return keywordSetRule(facts.keywordPaths, op, rule.value)
        case .filename:
            return stringRule(photo.filename, op, rule.value)
        case .rating:
            return intRule(photo.rating, op, rule.value)
        case .keywordCount:
            return intRule(facts.keywordPaths.count, op, rule.value)
        case .keywordGroup:
            // Inverted-by-exception (spec §7.3): only the two negative
            // operators negate; everything else reads as "has one".
            guard let groupId = Int64(rule.value) else { return false }
            let has = facts.keywordGroupIds.contains(groupId)
            return (op == .doesNotContain || op == .doesNotEqual) ? !has : has
        case .dateRange:
            return dateRule(photo.dateAdded, op, rule.value)
        case .captureDate:
            guard let captureDate = photo.captureDate else { return false }
            return dateRule(captureDate, op, rule.value)
        case .importBatch:
            return photo.importBatchId.map(String.init) == rule.value
        }
    }

    /// `contains`/`equals` = *any* keyword matches; the negatives are the
    /// exact logical negations (*no* keyword matches). Case-insensitive via
    /// the same folding as the search filter.
    private static func keywordSetRule(_ paths: [String], _ op: RuleOperator, _ value: String) -> Bool {
        switch op {
        case .contains:
            return paths.contains { CaseInsensitiveMatch.contains($0, value) }
        case .equals:
            return paths.contains { CaseInsensitiveMatch.equals($0, value) }
        case .doesNotContain:
            return !paths.contains { CaseInsensitiveMatch.contains($0, value) }
        case .doesNotEqual:
            return !paths.contains { CaseInsensitiveMatch.equals($0, value) }
        case .greaterThan, .lessThan:
            return false
        }
    }

    private static func stringRule(_ subject: String, _ op: RuleOperator, _ value: String) -> Bool {
        switch op {
        case .contains: return CaseInsensitiveMatch.contains(subject, value)
        case .equals: return CaseInsensitiveMatch.equals(subject, value)
        case .doesNotContain: return !CaseInsensitiveMatch.contains(subject, value)
        case .doesNotEqual: return !CaseInsensitiveMatch.equals(subject, value)
        case .greaterThan, .lessThan: return false
        }
    }

    /// `doesNotEqual` is implemented (U10) — the original silently returned
    /// false. Non-numeric values never match (spec §7.3).
    private static func intRule(_ subject: Int, _ op: RuleOperator, _ value: String) -> Bool {
        guard let number = Int(value.trimmingCharacters(in: .whitespaces)) else { return false }
        switch op {
        case .equals: return subject == number
        case .doesNotEqual: return subject != number
        case .greaterThan: return subject > number
        case .lessThan: return subject < number
        case .contains, .doesNotContain: return false
        }
    }

    /// Value is a Unix timestamp (seconds) as string; only ordering
    /// comparisons are meaningful for dates (spec §7.3).
    private static func dateRule(_ subject: Date, _ op: RuleOperator, _ value: String) -> Bool {
        guard let seconds = Double(value.trimmingCharacters(in: .whitespaces)) else { return false }
        let reference = Date(timeIntervalSince1970: seconds)
        switch op {
        case .greaterThan: return subject > reference
        case .lessThan: return subject < reference
        case .equals, .doesNotEqual, .contains, .doesNotContain: return false
        }
    }
}
