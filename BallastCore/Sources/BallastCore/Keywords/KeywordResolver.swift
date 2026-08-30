import Foundation

/// What typed keyword text resolves to (spec §8.4).
public enum KeywordResolution: Equatable, Sendable {
    /// An existing tree node — `"ANNA"` became `PEOPLE > TEAM > ANNA` (Q16).
    case existing(Int64)
    /// No match: normalized components to find-or-create as ad-hoc (grey) nodes.
    case create([String])
}

public enum KeywordResolver {
    /// Resolves raw field text. Single names are looked up depth-first across the
    /// whole tree, first match wins (Q16). Text containing the `" > "` separator
    /// (e.g. an accepted autocomplete suggestion, Q17) resolves as an exact path.
    /// Unmatched text is created uppercased as-is (spec §8.4 step 4).
    public static func resolve(_ input: String, tree: KeywordTree) -> KeywordResolution? {
        let components = input
            .components(separatedBy: KeywordTree.separator)
            .map(KeywordDAO.normalize)
            .filter { !$0.isEmpty }
        guard !components.isEmpty else { return nil }
        if components.count == 1 {
            if let id = tree.firstMatch(named: components[0]) {
                return .existing(id)
            }
        } else if let id = tree.find(pathComponents: components) {
            return .existing(id)
        }
        return .create(components)
    }

    /// The canonical text a keyword *binding* stores (C7): resolve exactly like
    /// the panel would, then render the result — an existing node becomes its
    /// full derived path, unmatched text stays as uppercased components. This
    /// keeps `keyword:anna` and the panel's `PEOPLE > ANNA` the same keyword.
    public static func canonicalText(_ input: String, tree: KeywordTree) -> String? {
        switch resolve(input, tree: tree) {
        case nil:
            return nil
        case .existing(let id):
            return tree.path(of: id)
        case .create(let components):
            return components.joined(separator: KeywordTree.separator)
        }
    }
}

/// Autocomplete over the whole tree: every node is offered, not just leaves (Q17).
/// Ad-hoc keywords are tree nodes too, so this is the spec's vocabulary∪index list.
public enum KeywordAutocomplete {
    /// U36: the dropdown's explicit escape from the Q16 first-match rule —
    /// non-nil when the input, read as an EXACT path, does not exist yet
    /// (a bare "2008" while only "JAHRE > 2008" is in the tree). Selecting
    /// the offered row creates and assigns exactly this path instead of
    /// resolving to the first name match somewhere in the tree.
    public static func createOption(for input: String, tree: KeywordTree) -> String? {
        let components = input
            .components(separatedBy: KeywordTree.separator)
            .map(KeywordDAO.normalize)
            .filter { !$0.isEmpty }
        guard !components.isEmpty, tree.find(pathComponents: components) == nil else { return nil }
        return components.joined(separator: KeywordTree.separator)
    }

    /// Filters the tree's precomputed folded corpus with one plain-`contains`
    /// pass — no path construction and no per-path ICU search per keystroke.
    public static func suggestions(for input: String, tree: KeywordTree) -> [String] {
        let needle = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let foldedNeedle = CaseInsensitiveMatch.fold(needle)
        return tree.allFoldedPaths()
            .filter { $0.folded.contains(foldedNeedle) }
            .map(\.path)
            // Same ordering as tree siblings and chips (Q19): "ÄPFEL" next to
            // "APFEL", numbers in natural order.
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// Highlight state of the autocomplete dropdown (spec §9.8 keyboard table):
/// ↓ wraps last→first; ↑ leaves the list from the first entry and enters it at
/// the last from "no highlight". Typing resets to "no highlight".
public struct AutocompleteHighlight: Equatable, Sendable {
    /// nil = no highlight, focus semantics stay in the field.
    public private(set) var index: Int?

    public init() {}

    public mutating func reset() {
        index = nil
    }

    public mutating func moveDown(count: Int) {
        guard count > 0 else { return index = nil }
        switch index {
        case nil: index = 0
        case let current?: index = (current + 1) % count
        }
    }

    public mutating func moveUp(count: Int) {
        guard count > 0 else { return index = nil }
        switch index {
        case nil: index = count - 1
        case 0: index = nil
        case let current?: index = current - 1
        }
    }

    /// Suggestion lists shrink while typing — keep the index valid.
    public mutating func clamp(count: Int) {
        if let current = index, current >= count {
            index = count > 0 ? count - 1 : nil
        }
    }
}
