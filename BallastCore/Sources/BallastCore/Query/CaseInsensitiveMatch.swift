import Foundation

/// The one case-insensitive comparison used by both the search filter and the
/// rule engine. Uses Foundation's case folding (not `lowercased()`), so
/// fold-sensitive input behaves identically everywhere — "ß" matches the "SS"
/// that `uppercased()` stores, in the search box and in a keyword rule alike.
public enum CaseInsensitiveMatch {
    public static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: .caseInsensitive) != nil
    }

    public static func equals(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// The one canonical case fold. Two folded strings compare with plain
    /// `==`/`contains` and agree with the ICU-based functions above — hot
    /// paths fold once (keyword paths at tree construction, rule values at
    /// compile time) instead of running ICU per comparison.
    public static func fold(_ string: String) -> String {
        string.folding(options: .caseInsensitive, locale: nil)
    }
}
