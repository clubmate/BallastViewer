import BallastCore
import SwiftUI

/// U49: the keyword picker of a profile answer — a search field over the
/// library's keyword paths instead of a menu with every path in it (a
/// Lightroom-sized tree has thousands). Type to filter, click to pick, ✕ to
/// unmap. Uses the same dropdown as the inspector's Add Keyword field.
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
        .overlay(alignment: .topLeading) {
            if focused, !suggestions.isEmpty {
                SuggestionDropdown(suggestions: suggestions) { pick($0) }
                    .frame(width: 320, height: SuggestionDropdown.height(forCount: suggestions.count))
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 4)
                    .offset(y: 26)
                    .zIndex(10)
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
