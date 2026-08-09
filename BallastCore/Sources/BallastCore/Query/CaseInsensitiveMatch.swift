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
}
