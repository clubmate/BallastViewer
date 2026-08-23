import AppKit
import BallastCore
import SwiftUI

/// Right panel per spec §9.8: filename, rating stars, ADD KEYWORD with
/// autocomplete, assigned chips (intersection, Q14), Reveal in Finder footer.
struct InspectorView: View {
    @Environment(LibraryController.self) private var controller
    @Environment(CenterViewModel.self) private var center

    @State private var keywordInput = ""
    @State private var highlight = AutocompleteHighlight()
    @FocusState private var keywordFieldFocused: Bool

    var body: some View {
        // The inspector renders from `selectionSummary` — the aggregates
        // (title, shared rating, chip intersection) are computed once per
        // relevant change in CenterViewModel, not per body pass. Actions
        // materialise the id list lazily at click time.
        let summary = center.selectionSummary
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    title(summary)
                    ratingStars(summary)
                    keywordEntry(hasSelection: summary.count > 0)
                        .zIndex(1)
                    chipList(summary)
                }
                .padding(10)
            }
            Divider()
            footer(hasSelection: summary.count > 0)
        }
    }

    /// The whole selection, materialised at ACTION time only.
    private var selectedIds: [Int64] {
        Array(center.selection.selectedIds)
    }

    // MARK: Title (spec §9.8 item 1)

    private func title(_ summary: CenterViewModel.SelectionSummary) -> some View {
        Text(summary.title)
            .font(.title)
            .textSelection(.enabled)
            .lineLimit(2)
    }

    // MARK: Rating (Q12, U3, U4)

    private func ratingStars(_ summary: CenterViewModel.SelectionSummary) -> some View {
        let current = summary.sharedRating
        let isMixed = summary.isMixed
        return HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                let filled = star <= (current ?? 0)
                Button {
                    let ids = selectedIds
                    guard !ids.isEmpty else { return }
                    // Q12: tapping the current rating is the mouse route to 0.
                    let value = star == current ? 0 : star
                    controller.updateRatings(ids: ids) { _ in value }
                } label: {
                    Image(systemName: filled ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(filled ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(star == 1 ? "1 star" : "\(star) stars")
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
        // The vocabulary mirror, not `snapshot` — see LibraryController.vocabulary.
        KeywordAutocomplete.suggestions(for: keywordInput, tree: controller.vocabulary.tree)
    }

    private func keywordEntry(hasSelection: Bool) -> some View {
        // Focus-guarded: leftover text in an unfocused field must not filter
        // the whole vocabulary on every unrelated body pass.
        let suggestions = keywordFieldFocused ? self.suggestions : []
        return HStack(spacing: 6) {
            TextField("Add Keyword", text: $keywordInput)
                .textFieldStyle(.plain)
                .focused($keywordFieldFocused)
                // Q15: the field itself forces uppercase on every keystroke.
                .uppercasing($keywordInput)
                .onChange(of: keywordInput) { _, _ in
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
                .onKeyPress(.escape) {
                    // Hand the keyboard back to the grid (Q21 suppresses
                    // shortcuts while the field has focus).
                    keywordInput = ""
                    highlight.reset()
                    keywordFieldFocused = false
                    return .handled
                }
                .onKeyPress(.return) {
                    // Bounds-checked: the vocabulary can shrink (keyword
                    // deleted in Settings) between the body pass that built
                    // `suggestions` and this key press.
                    let highlighted = highlight.index.flatMap { index in
                        suggestions.indices.contains(index) ? suggestions[index] : nil
                    }
                    commit(highlighted)
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
        // No selection: nothing to assign to, so the field and "+" are dead.
        // Bulk transactions (import, metadata load, folder undo) shield the
        // main window but not this field: creating an unknown keyword is a
        // synchronous structural write — see LibraryController.writeSync.
        .disabled(!hasSelection || controller.isBusy)
        .roundedFieldChrome()
        .overlay(alignment: .topLeading) {
            // Dropdown overlays below the field (spec §9.8: offset 45).
            if keywordFieldFocused && !suggestions.isEmpty {
                SuggestionDropdown(
                    suggestions: suggestions, highlightIndex: highlight.index, rowHeight: 35
                ) { commit($0) }
                .offset(y: 45)
            }
        }
    }

    /// Accepts the highlighted suggestion when given, otherwise the raw text
    /// (spec §9.8 Return semantics). Assigns to the whole selection (U3).
    private func commit(_ suggestion: String?) {
        let text = suggestion ?? keywordInput
        let ids = selectedIds
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !ids.isEmpty else { return }
        guard !controller.isBusy else {
            controller.errorMessage = LibraryController.busyMessage
            return
        }
        controller.assignKeyword(text: text, toPhotoIds: ids)
        keywordInput = ""
        highlight.reset()
        // Hand the keyboard back to the grid right away: the usual flow is
        // "keyword, then arrow to the next photo" (Q21 would otherwise swallow
        // the arrow). Click the field again to add another keyword.
        keywordFieldFocused = false
    }

    // MARK: Chips (Q14 intersection, Q18 order)

    @ViewBuilder
    private func chipList(_ summary: CenterViewModel.SelectionSummary) -> some View {
        if summary.chips.isEmpty {
            if summary.count > 0 {
                Text("No keywords assigned")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 6) {
                ForEach(summary.chips) { chip in
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

    // MARK: Footer (Reveal in Finder)

    private func footer(hasSelection: Bool) -> some View {
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
        }
        .disabled(!hasSelection)
        .padding(.horizontal, 10)
        .frame(height: PanelMetrics.footerHeight)
    }
}
