import AppKit
import BallastCore
import SwiftUI

/// Right panel per spec §9.8: filename, rating stars, ADD KEYWORD with
/// autocomplete, assigned chips (intersection, Q14), Reveal/Share footer.
struct InspectorView: View {
    @Environment(LibraryController.self) private var controller
    @Environment(CenterViewModel.self) private var center

    @State private var keywordInput = ""
    @State private var highlight = AutocompleteHighlight()
    @FocusState private var keywordFieldFocused: Bool

    private var selectedIds: [Int64] {
        Array(center.selection.selectedIds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    title
                    ratingStars
                    keywordEntry
                        .zIndex(1)
                    chipList
                }
                .padding(10)
            }
            Divider()
            footer
        }
        .background(.bar)
    }

    // MARK: Title (spec §9.8 item 1)

    private var title: some View {
        let text: String
        switch selectedIds.count {
        case 0: text = "No Selection"
        case 1:
            text = center.selection.anchorId
                .flatMap { controller.photo(withId: $0)?.filename } ?? "1 Photo Selected"
        case let n: text = "\(n) Photos Selected"
        }
        return Text(text)
            .font(.title)
            .textSelection(.enabled)
            .lineLimit(2)
    }

    // MARK: Rating (Q12, U3, U4)

    /// The shared rating, or nil when the selection disagrees (mixed).
    private var sharedRating: Int? {
        let ratings = Set(selectedIds.compactMap { controller.photo(withId: $0)?.rating })
        return ratings.count == 1 ? ratings.first : nil
    }

    private var ratingStars: some View {
        let current = sharedRating
        let isMixed = current == nil && !selectedIds.isEmpty
        return HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                let filled = star <= (current ?? 0)
                Image(systemName: filled ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(filled ? Color.yellow : Color.secondary)
                    .onTapGesture {
                        guard !selectedIds.isEmpty else { return }
                        // Q12: tapping the current rating is the mouse route to 0.
                        let value = star == current ? 0 : star
                        controller.updateRatings(ids: selectedIds) { _ in value }
                    }
            }
            if isMixed {
                // U4: a mixed selection is not displayed as "unrated".
                Text("MIXED")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    // MARK: ADD KEYWORD (Q15/Q16/Q17, spec §9.8 keyboard table)

    private var suggestions: [String] {
        guard let tree = controller.snapshot?.keywordTree else { return [] }
        return KeywordAutocomplete.suggestions(for: keywordInput, tree: tree)
    }

    private var keywordEntry: some View {
        let suggestions = self.suggestions
        return HStack(spacing: 6) {
            TextField("Add Keyword", text: $keywordInput)
                .textFieldStyle(.plain)
                .focused($keywordFieldFocused)
                .onChange(of: keywordInput) { _, newValue in
                    // Q15: the field itself forces uppercase on every keystroke.
                    let upper = newValue.uppercased()
                    if upper != newValue { keywordInput = upper }
                    // Typing resets the highlight (spec §9.8).
                    highlight.reset()
                }
                .onKeyPress(.downArrow) {
                    guard !suggestions.isEmpty else { return .ignored }
                    highlight.moveDown(count: suggestions.count)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !suggestions.isEmpty else { return .ignored }
                    highlight.moveUp(count: suggestions.count)
                    return .handled
                }
                .onKeyPress(.return) {
                    commit(highlight.index.map { suggestions[$0] })
                    return .handled
                }
            Button {
                commit(nil)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(keywordInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            // Dropdown overlays below the field (spec §9.8: offset 45).
            if keywordFieldFocused && !suggestions.isEmpty {
                suggestionList(suggestions)
                    .offset(y: 45)
            }
        }
    }

    private func suggestionList(_ suggestions: [String]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element) { index, path in
                        Text(path)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .frame(height: 35)
                            .background(
                                highlight.index == index
                                    ? Color.accentColor.opacity(0.3) : Color.clear
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { commit(path) }
                            .id(index)
                    }
                }
            }
            .frame(height: min(CGFloat(suggestions.count) * 35, 150))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4)
            .onChange(of: highlight) {
                if let index = highlight.index {
                    proxy.scrollTo(index)
                }
            }
        }
    }

    /// Accepts the highlighted suggestion when given, otherwise the raw text
    /// (spec §9.8 Return semantics). Assigns to the whole selection (U3).
    private func commit(_ suggestion: String?) {
        let text = suggestion ?? keywordInput
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !selectedIds.isEmpty else { return }
        controller.assignKeyword(text: text, toPhotoIds: selectedIds)
        keywordInput = ""
        highlight.reset()
    }

    // MARK: Chips (Q14 intersection, Q18 order)

    private var chips: [KeywordChip] {
        guard let snapshot = controller.snapshot else { return [] }
        let common = KeywordChipBuilder.commonKeywordIds(
            photoIds: selectedIds, keywordIdsByPhoto: snapshot.keywordIdsByPhoto
        )
        return KeywordChipBuilder.chips(
            forKeywordIds: common, tree: snapshot.keywordTree, groups: snapshot.keywordGroups
        )
    }

    @ViewBuilder
    private var chipList: some View {
        let chips = self.chips
        if chips.isEmpty {
            if !selectedIds.isEmpty {
                Text("No keywords assigned")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 6) {
                ForEach(chips) { chip in
                    chipRow(chip)
                }
            }
        }
    }

    private func chipRow(_ chip: KeywordChip) -> some View {
        // Ungrouped keywords render grey (spec §8.5).
        let color = chip.colorHex.flatMap(Color.init(hex:)) ?? Color.gray
        return HStack {
            Text(chip.path)
                .font(.title3)
                .lineLimit(1)
            Spacer()
            Button {
                controller.removeKeyword(id: chip.id, fromPhotoIds: selectedIds)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color, lineWidth: 1)
        )
    }

    // MARK: Footer (Reveal in Finder + Share)

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            Button {
                // Acts on the anchor — the "first" selected photo (spec §9.8).
                if let anchorId = center.selection.anchorId,
                   let photo = controller.photo(withId: anchorId) {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: photo.path)]
                    )
                }
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")

            ShareLink(items: selectedIds.compactMap { id in
                controller.photo(withId: id).map { URL(fileURLWithPath: $0.path) }
            }) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help("Share")
        }
        .disabled(selectedIds.isEmpty)
        .padding(.horizontal, 10)
        .frame(height: PanelMetrics.footerHeight)
    }
}
