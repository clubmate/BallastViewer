import SwiftUI

/// Keyword autocomplete dropdown shared by the bottom-bar search and the
/// inspector's Add Keyword field (spec §9.8/§11.3): a scrolling list of full
/// paths, optional keyboard highlight that scrolls into view, click picks.
struct SuggestionDropdown: View {
    let suggestions: [String]
    /// Keyboard-highlighted row (spec §9.8 ↑/↓); nil = none. Indexes run over
    /// the suggestions, then the create row (when present) as the last index.
    var highlightIndex: Int? = nil
    var rowHeight: CGFloat = 28
    /// U36: exact path offered as an explicit "Create" row below the matches —
    /// the escape from the Q16 first-match resolution. nil = no such row.
    var createOption: String? = nil
    var onCreate: (String) -> Void = { _ in }
    let onPick: (String) -> Void

    static let defaultRowHeight: CGFloat = 28
    static let maxHeight: CGFloat = 150

    /// The rendered height for `count` rows — callers that position the
    /// dropdown (offset above a field) need the same number the body uses.
    static func height(forCount count: Int, rowHeight: CGFloat = defaultRowHeight) -> CGFloat {
        min(CGFloat(count) * rowHeight, maxHeight)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element) { index, path in
                        Button {
                            onPick(path)
                        } label: {
                            Text(path)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .frame(height: rowHeight)
                                .background(
                                    highlightIndex == index
                                        ? Color.accentColor.opacity(0.3) : Color.clear
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                    if let createOption {
                        Button {
                            onCreate(createOption)
                        } label: {
                            Label("Create “\(createOption)”", systemImage: "plus")
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .frame(height: rowHeight)
                                .background(
                                    highlightIndex == suggestions.count
                                        ? Color.accentColor.opacity(0.3) : Color.clear
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(suggestions.count)
                    }
                }
            }
            .frame(height: Self.height(
                forCount: suggestions.count + (createOption == nil ? 0 : 1), rowHeight: rowHeight
            ))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4)
            .onChange(of: highlightIndex) {
                if let highlightIndex {
                    proxy.scrollTo(highlightIndex)
                }
            }
        }
    }
}

extension View {
    /// The plain-text-field chrome used in the bars: a controlBackgroundColor
    /// rounded rect with a separator stroke — a bordered field is invisible
    /// against the bar material.
    func roundedFieldChrome() -> some View {
        background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }
}
