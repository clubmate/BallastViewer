import BallastCore
import SwiftUI

/// U49: the keyword picker of a questionnaire answer — a search field over
/// the library's keyword paths instead of a menu with every path in it (a
/// Lightroom-sized tree has thousands). Type to filter, click to pick, ✕ to
/// unmap.
///
/// The dropdown is NOT drawn here: an overlay inside a form row lies
/// underneath the rows that follow, and their text fields swallow the
/// clicks (user report 2026-09-04: "you click through the list onto the
/// field below"). Instead the field publishes its bounds and suggestions
/// as a preference, and the enclosing view draws the list above everything
/// with `keywordDropdownHost()`.
struct KeywordPathField: View {
    @Environment(LibraryController.self) private var controller
    @Binding var keywordId: Int64?

    @State private var query = ""
    @FocusState private var focused: Bool

    private var tree: KeywordTree? { controller.snapshot?.keywordTree }

    private var currentPath: String? {
        guard let keywordId, let tree, tree.node(keywordId) != nil else { return nil }
        return tree.path(of: keywordId)
    }

    private var suggestions: [String] {
        guard let tree, focused else { return [] }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let paths = tree.allIdsDepthFirst().map { tree.path(of: $0) }
        let matches = needle.isEmpty ? paths : paths.filter { $0.lowercased().contains(needle) }
        return Array(matches.prefix(12))
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField(
                "", text: $query,
                prompt: Text(currentPath ?? "No keyword — type to search")
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit {
                if let first = suggestions.first { pick(first) }
            }
            .anchorPreference(key: KeywordDropdownKey.self, value: .bounds) { anchor in
                let suggestions = suggestions
                guard focused, !suggestions.isEmpty else { return nil }
                return KeywordDropdownRequest(anchor: anchor, suggestions: suggestions, pick: pick)
            }
            if keywordId != nil {
                Button {
                    keywordId = nil
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Assign no keyword for this answer")
            }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { query = "" }
        }
    }

    private func pick(_ path: String) {
        guard let tree else { return }
        let components = path.split(separator: " > ").map(String.init)
        keywordId = tree.find(pathComponents: components)
        query = ""
        focused = false
    }
}

/// What the focused `KeywordPathField` asks its host to draw.
struct KeywordDropdownRequest: @unchecked Sendable {
    let anchor: Anchor<CGRect>
    let suggestions: [String]
    let pick: (String) -> Void
}

struct KeywordDropdownKey: PreferenceKey {
    static let defaultValue: KeywordDropdownRequest? = nil
    static func reduce(value: inout KeywordDropdownRequest?, nextValue: () -> KeywordDropdownRequest?) {
        if let next = nextValue() { value = next }
    }
}

extension View {
    /// Draws the dropdown of whichever `KeywordPathField` below is focused,
    /// on top of the whole view — so it is never hidden behind, or beaten
    /// to the click by, later rows. Opens downwards, or upwards when there
    /// is no room below.
    func keywordDropdownHost() -> some View {
        overlayPreferenceValue(KeywordDropdownKey.self) { request in
            GeometryReader { geometry in
                if let request {
                    let field = geometry[request.anchor]
                    let height = SuggestionDropdown.height(forCount: request.suggestions.count)
                    let width = min(max(field.width, 320), max(200, geometry.size.width - field.minX - 8))
                    let fitsBelow = field.maxY + 2 + height <= geometry.size.height
                    SuggestionDropdown(suggestions: request.suggestions, onPick: request.pick)
                        .frame(width: width, height: height)
                        .position(
                            x: field.minX + width / 2,
                            y: fitsBelow ? field.maxY + 2 + height / 2 : field.minY - 2 - height / 2
                        )
                }
            }
        }
    }
}
