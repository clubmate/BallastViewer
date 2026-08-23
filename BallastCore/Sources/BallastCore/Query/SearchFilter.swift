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

    /// A query folded once per filter pass (`nil` = blank query = search off),
    /// so the per-photo test is plain `contains` on precomputed folded strings
    /// instead of an ICU search per photo per keyword path.
    public struct FoldedQuery: Sendable {
        public let folded: String

        /// Returns nil for a blank query — callers skip the filter entirely.
        public init?(_ query: String) {
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return nil }
            folded = CaseInsensitiveMatch.fold(needle)
        }

        /// `facts.foldedFilename` / `facts.foldedKeywordPaths` come from the
        /// facts cache and tree memo; when not precomputed (nil / count
        /// mismatch) the strings are folded on the fly so the result still
        /// equals `SearchFilter.matches`.
        public func matches(filename: String, facts: PhotoQueryFacts) -> Bool {
            if facts.foldedFilename(or: filename).contains(folded) { return true }
            if facts.foldedKeywordPaths.count == facts.keywordPaths.count {
                return facts.foldedKeywordPaths.contains { $0.contains(folded) }
            }
            return facts.keywordPaths.contains { CaseInsensitiveMatch.fold($0).contains(folded) }
        }
    }
}
