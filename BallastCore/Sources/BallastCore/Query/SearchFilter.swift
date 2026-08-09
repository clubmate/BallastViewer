import Foundation

/// The bottom-bar search (spec §11.3): case-insensitive substring, applied on
/// top of the active collection. U5 extends matching to filenames — the
/// original searched keywords only, despite having a filename rule (C6 family).
public enum SearchFilter {
    /// True when the query hits the filename or any derived keyword path.
    /// A blank query matches everything (search off).
    public static func matches(filename: String, keywordPaths: [String], query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        if CaseInsensitiveMatch.contains(filename, needle) { return true }
        return keywordPaths.contains { CaseInsensitiveMatch.contains($0, needle) }
    }
}
