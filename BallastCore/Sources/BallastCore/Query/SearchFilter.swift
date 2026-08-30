import Foundation

/// The bottom-bar search (spec §11.3): case-insensitive substring, applied on
/// top of the active collection. U5 extends matching to filenames — the
/// original searched keywords only, despite having a filename rule (C6 family).
/// U37: whitespace splits the query into OR terms — "PARIS ROME" shows every
/// photo matching PARIS or ROME (each term still hits keywords AND filenames).
public enum SearchFilter {
    /// True when ANY term hits the filename or a derived keyword path.
    /// A blank query matches everything (search off).
    public static func matches(filename: String, keywordPaths: [String], query: String) -> Bool {
        guard let folded = FoldedQuery(query) else { return true }
        return folded.matches(
            filename: filename, facts: PhotoQueryFacts(keywordPaths: keywordPaths)
        )
    }

    /// A query folded once per filter pass (`nil` = blank query = search off),
    /// so the per-photo test is plain `contains` on precomputed folded strings
    /// instead of an ICU search per photo per keyword path.
    public struct FoldedQuery: Sendable {
        /// The whitespace-separated terms, folded — OR-combined (U37).
        public let terms: [String]

        /// Returns nil for a blank query — callers skip the filter entirely.
        /// A `>` token glues its neighbours into ONE path term, so
        /// "LOCATION > ROME PARIS" searches for "LOCATION > ROME" OR "PARIS"
        /// instead of degenerating into a match-everything ">" term.
        public init?(_ query: String) {
            var terms: [String] = []
            var pending: String?
            var joinNext = false
            for token in query.split(whereSeparator: \.isWhitespace) {
                if token == ">" {
                    // Needs a left side; a stray leading ">" is dropped.
                    joinNext = pending != nil
                    continue
                }
                if joinNext, let left = pending {
                    pending = left + " > " + token
                    joinNext = false
                } else {
                    if let left = pending { terms.append(left) }
                    pending = String(token)
                }
            }
            if let left = pending { terms.append(left) }
            guard !terms.isEmpty else { return nil }
            self.terms = terms.map(CaseInsensitiveMatch.fold)
        }

        /// `facts.foldedFilename` / `facts.foldedKeywordPaths` come from the
        /// facts cache and tree memo; when not precomputed (nil / count
        /// mismatch) the strings are folded on the fly so the result still
        /// equals `SearchFilter.matches`.
        public func matches(filename: String, facts: PhotoQueryFacts) -> Bool {
            let foldedFilename = facts.foldedFilename(or: filename)
            let foldedPaths = facts.foldedKeywordPaths.count == facts.keywordPaths.count
                ? facts.foldedKeywordPaths
                : facts.keywordPaths.map(CaseInsensitiveMatch.fold)
            return terms.contains { term in
                foldedFilename.contains(term) || foldedPaths.contains { $0.contains(term) }
            }
        }
    }
}
