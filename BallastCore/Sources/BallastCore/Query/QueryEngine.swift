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

    public init(keywordPaths: [String] = [], keywordGroupIds: Set<Int64> = []) {
        self.keywordPaths = keywordPaths
        self.keywordGroupIds = keywordGroupIds
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
    /// exact logical negations (*no* keyword matches). Case-insensitive.
    private static func keywordSetRule(_ paths: [String], _ op: RuleOperator, _ value: String) -> Bool {
        let needle = value.lowercased()
        switch op {
        case .contains:
            return paths.contains { $0.lowercased().contains(needle) }
        case .equals:
            return paths.contains { $0.lowercased() == needle }
        case .doesNotContain:
            return !paths.contains { $0.lowercased().contains(needle) }
        case .doesNotEqual:
            return !paths.contains { $0.lowercased() == needle }
        case .greaterThan, .lessThan:
            return false
        }
    }

    private static func stringRule(_ subject: String, _ op: RuleOperator, _ value: String) -> Bool {
        let haystack = subject.lowercased()
        let needle = value.lowercased()
        switch op {
        case .contains: return haystack.contains(needle)
        case .equals: return haystack == needle
        case .doesNotContain: return !haystack.contains(needle)
        case .doesNotEqual: return haystack != needle
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
