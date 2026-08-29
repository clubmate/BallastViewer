import AppKit
import BallastCore
import SwiftUI

/// Collapsible keyword-tree section at the bottom of the inspector (U29):
/// the full keyword hierarchy with subtree-inclusive photo counts in
/// parentheses. Clicking a keyword shows every photo carrying it or a
/// descendant (globally — the sidebar selection is replaced and an active
/// search discarded). The expanded section's height is draggable via the
/// handle above the header; default is 30% of the panel.
struct KeywordTreeSection: View {
    @Environment(LibraryController.self) private var controller
    @Environment(CenterViewModel.self) private var center
    @Environment(KeywordPanelModel.self) private var model

    /// Full inspector height — the 30% default and the drag clamp need it.
    let panelHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if model.isExpanded {
                SectionResizeHandle(
                    height: Binding(
                        get: { model.sectionHeight },
                        set: { model.sectionHeight = $0 }
                    ),
                    current: effectiveHeight,
                    range: heightRange
                )
            } else {
                Divider()
            }
            header
            if model.isExpanded {
                content
                    .frame(height: effectiveHeight)
            }
        }
    }

    // MARK: Geometry

    /// Sensible even in a tiny window: never taller than what leaves the
    /// title + keyword entry visible above.
    private var heightRange: ClosedRange<CGFloat> {
        let upper = max(80, panelHeight - 220)
        return 80...upper
    }

    private var effectiveHeight: CGFloat {
        let stored = CGFloat(model.sectionHeight)
        let raw = stored > 0 ? stored : panelHeight * 0.3
        return min(heightRange.upperBound, max(heightRange.lowerBound, raw))
    }

    // MARK: Header

    private var header: some View {
        Button {
            model.isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Text("KEYWORDS")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Tree

    /// First level: the keyword groups (Settings ▸ Keywords order), then the
    /// UNGROUPED pseudo-group — root keywords bucketed by their effective
    /// group, exactly like the settings list.
    @ViewBuilder
    private var content: some View {
        let tree = controller.vocabulary.tree
        if tree.isEmpty {
            VStack {
                Spacer()
                Text("No keywords yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            let groups = controller.vocabulary.groups
            let ungrouped = tree.rootIds.filter { tree.effectiveGroupId(of: $0) == nil }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groups) { group in
                        let groupId = group.id ?? KeywordCounts.ungroupedKey
                        let roots = tree.rootIds.filter { tree.effectiveGroupId(of: $0) == groupId }
                        KeywordGroupRow(name: group.name, groupId: groupId)
                        if model.expandedGroups.contains(groupId) {
                            KeywordTreeRows(tree: tree, ids: roots, level: 1)
                        }
                    }
                    if !ungrouped.isEmpty {
                        let sentinel = KeywordCounts.ungroupedKey
                        KeywordGroupRow(name: "UNGROUPED", groupId: sentinel)
                        if model.expandedGroups.contains(sentinel) {
                            KeywordTreeRows(tree: tree, ids: ungrouped, level: 1)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// First-level group row: whole row toggles disclosure, count pill on the
/// right (photos with ≥1 keyword of the group, deduped).
private struct KeywordGroupRow: View {
    @Environment(KeywordPanelModel.self) private var model

    let name: String
    let groupId: Int64

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .rotationEffect(.degrees(model.expandedGroups.contains(groupId) ? 90 : 0))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            CountPill(count: model.counts.byGroup[groupId] ?? 0, selected: false)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 24)
        .contentShape(Rectangle())
        .onTapGesture {
            model.toggleGroup(groupId)
        }
    }
}

/// The sidebar's count-badge recipe (SidebarView.rowLabel), shared by group
/// and keyword rows.
private struct CountPill: View {
    let count: Int
    let selected: Bool

    var body: some View {
        Text("\(count)")
            .font(.caption)
            .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(
                    selected ? AnyShapeStyle(.white.opacity(0.2))
                        : AnyShapeStyle(.secondary.opacity(0.2))
                )
            )
    }
}

/// One level of the tree; recurses for expanded nodes.
private struct KeywordTreeRows: View {
    @Environment(KeywordPanelModel.self) private var model

    let tree: KeywordTree
    let ids: [Int64]
    let level: Int

    var body: some View {
        ForEach(ids, id: \.self) { id in
            KeywordTreeRow(
                tree: tree,
                id: id,
                level: level,
                hasChildren: !tree.children(of: id).isEmpty
            )
            if model.expandedNodes.contains(id) {
                KeywordTreeRows(tree: tree, ids: tree.children(of: id), level: level + 1)
            }
        }
    }
}

private struct KeywordTreeRow: View {
    @Environment(CenterViewModel.self) private var center
    @Environment(KeywordPanelModel.self) private var model

    let tree: KeywordTree
    let id: Int64
    let level: Int
    let hasChildren: Bool

    var body: some View {
        let selected = center.activeItem == .keyword(id)
        HStack(spacing: 2) {
            // The disclosure chevron toggles the node WITHOUT firing the
            // row's filter action — a separate button, not part of the tap.
            Button {
                model.toggleNode(id)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(model.expandedNodes.contains(id) ? 90 : 0))
                    .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hasChildren ? 1 : 0)
            .disabled(!hasChildren)

            Text(tree.node(id)?.name ?? "?")
                .lineLimit(1)
            Spacer(minLength: 4)
            CountPill(count: model.counts.byKeyword[id] ?? 0, selected: selected)
        }
        .font(.callout)
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.leading, 6 + CGFloat(level) * 14)
        .padding(.trailing, 8)
        .frame(height: 24)
        .contentShape(Rectangle())
        .background(selected ? Color.accentColor : Color.clear)
        .onTapGesture {
            center.filterByKeyword(id)
        }
    }
}

/// Horizontal twin of PaneDivider: a 1 pt line with a taller invisible grab
/// strip; dragging up grows the section (its bottom edge is pinned).
private struct SectionResizeHandle: View {
    @Binding var height: Double
    /// The rendered height at drag start (the stored value can be 0 =
    /// "default 30%", so the drag must base itself on what is on screen).
    let current: CGFloat
    let range: ClosedRange<CGFloat>

    @State private var dragBase: CGFloat?
    @State private var hovered = false
    @State private var cursorPushed = false

    var body: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(height: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hovered = inside
                        if inside { pushCursor() } else if dragBase == nil { popCursor() }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                if dragBase == nil { dragBase = current }
                                pushCursor()
                                let proposed = dragBase! - value.translation.height
                                height = Double(min(range.upperBound, max(range.lowerBound, proposed)))
                            }
                            .onEnded { _ in
                                dragBase = nil
                                if !hovered { popCursor() }
                            }
                    )
                    .onDisappear(perform: popCursor)
            }
    }

    private func pushCursor() {
        guard !cursorPushed else { return }
        cursorPushed = true
        NSCursor.resizeUpDown.push()
    }

    private func popCursor() {
        guard cursorPushed else { return }
        cursorPushed = false
        NSCursor.pop()
    }
}
