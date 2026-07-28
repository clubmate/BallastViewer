import BallastCore
import SwiftUI
import UniformTypeIdentifiers

/// The fixed nine-colour palette for keyword groups (spec §8.6).
let keywordGroupPalette: [String] = [
    "#FF3B30", "#FF9500", "#FFCC00", "#4CD964", "#5AC8FA",
    "#007AFF", "#5856D6", "#FF2D55", "#8E8E93",
]

/// Settings ▸ Keywords — the vocabulary tree editor (spec §8.6).
/// Ad-hoc keywords (no group) are deliberately not listed, reproducing the
/// original's vocabulary/index split. Group order is drag-editable and drives
/// chip sort priority (Q18).
struct KeywordsSettingsView: View {
    @Environment(LibraryController.self) private var controller

    @State private var draggedGroupId: Int64?
    @State private var collapsedGroups: Set<Int64> = []
    @State private var collapsedKeywords: Set<Int64> = []
    @State private var colorPopoverGroupId: Int64?
    @State private var editingGroup: KeywordGroupRecord?
    /// Rename target + working text; nil id = closed.
    @State private var renameKeywordId: Int64?
    @State private var renameText = ""
    @State private var pendingKeywordDeletion: Int64?
    @State private var pendingGroupDeletion: KeywordGroupRecord?

    private var tree: KeywordTree? { controller.snapshot?.keywordTree }

    var body: some View {
        Group {
            if let snapshot = controller.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(snapshot.keywordGroups) { group in
                            groupSection(group, tree: snapshot.keywordTree)
                        }
                    }
                    .padding(12)
                }
            } else {
                Text("No library open")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $editingGroup) { group in
            GroupEditSheet(group: group) { name, color in
                if let id = group.id {
                    controller.renameKeywordGroup(id, to: name)
                    controller.setKeywordGroupColor(id, color: color)
                }
            }
        }
        .alert(
            "Rename Keyword",
            isPresented: Binding(
                get: { renameKeywordId != nil },
                set: { if !$0 { renameKeywordId = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let id = renameKeywordId {
                    controller.renameKeyword(id, to: renameText)
                }
                renameKeywordId = nil
            }
            // Cancelling after "+" keeps the freshly created node — the
            // spec §8.6 quirk is preserved deliberately.
            Button("Cancel", role: .cancel) { renameKeywordId = nil }
        }
        .alert(
            "Delete Keyword",
            isPresented: Binding(
                get: { pendingKeywordDeletion != nil },
                set: { if !$0 { pendingKeywordDeletion = nil } }
            ),
            presenting: pendingKeywordDeletion
        ) { id in
            Button("Delete", role: .destructive) {
                controller.deleteKeywordSubtree(id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { id in
            Text(keywordDeletionMessage(id))
        }
        .alert(
            "Delete Group",
            isPresented: Binding(
                get: { pendingGroupDeletion != nil },
                set: { if !$0 { pendingGroupDeletion = nil } }
            ),
            presenting: pendingGroupDeletion
        ) { group in
            Button("Delete", role: .destructive) {
                if let id = group.id { controller.deleteKeywordGroup(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { group in
            Text(groupDeletionMessage(group))
        }
    }

    // MARK: Alert messages (U7: destructive actions state their blast radius)

    private func keywordDeletionMessage(_ id: Int64) -> String {
        let impact = controller.keywordDeletionImpact(id)
        let path = tree?.path(of: id) ?? ""
        var message = "Delete “\(path)”"
        if impact.keywordCount > 1 {
            let subCount = impact.keywordCount - 1
            message += " and its \(subCount) sub-keyword\(subCount == 1 ? "" : "s")"
        }
        message += "?\nIt will be removed from \(impact.photoCount) photo\(impact.photoCount == 1 ? "" : "s")."
        return message
    }

    /// C3 fix: members become ad-hoc, and referencing rules get a warning.
    private func groupDeletionMessage(_ group: KeywordGroupRecord) -> String {
        let impact = group.id.map(controller.groupDeletionImpact) ?? (keywordCount: 0, ruleCount: 0)
        var message = "Delete the group “\(group.name)”?\n"
        message += "Its \(impact.keywordCount) keyword\(impact.keywordCount == 1 ? "" : "s") will become ungrouped (grey)."
        if impact.ruleCount > 0 {
            message += "\n⚠︎ \(impact.ruleCount) Smart Collection rule\(impact.ruleCount == 1 ? "" : "s") "
            message += impact.ruleCount == 1 ? "references" : "reference"
            message += " this group and will stop matching."
        }
        return message
    }

    // MARK: Group section

    @ViewBuilder
    private func groupSection(_ group: KeywordGroupRecord, tree: KeywordTree) -> some View {
        if let groupId = group.id {
            let topLevel = tree.rootIds.filter { tree.node($0)?.groupId == groupId }
            let collapsed = collapsedGroups.contains(groupId)

            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .foregroundStyle(.secondary)

                Button {
                    colorPopoverGroupId = groupId
                } label: {
                    Circle()
                        .fill(Color(hex: group.color) ?? .gray)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .popover(
                    isPresented: Binding(
                        get: { colorPopoverGroupId == groupId },
                        set: { if !$0 { colorPopoverGroupId = nil } }
                    )
                ) {
                    palettePicker(selected: group.color) { color in
                        controller.setKeywordGroupColor(groupId, color: color)
                        colorPopoverGroupId = nil
                    }
                }

                // n counts only the group's top-level definitions (spec §8.6).
                Text("\(group.name) (\(topLevel.count))")
                    .fontWeight(.bold)

                Spacer()

                Button {
                    addKeyword(parentId: nil, groupId: groupId, base: "NEW KEYWORD")
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { editingGroup = group }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if collapsed {
                        collapsedGroups.remove(groupId)
                    } else {
                        collapsedGroups.insert(groupId)
                    }
                }
            }
            .contextMenu {
                Button("Rename") { editingGroup = group }
                Button("Delete Group", role: .destructive) { pendingGroupDeletion = group }
            }
            .onDrag {
                draggedGroupId = groupId
                return NSItemProvider(object: "keywordGroup:\(groupId)" as NSString)
            }
            .onDrop(
                of: [UTType.plainText],
                delegate: RowReorderDelegate(
                    targetId: groupId,
                    draggedId: $draggedGroupId,
                    orderedIds: (controller.snapshot?.keywordGroups ?? []).compactMap(\.id),
                    reorder: { controller.reorderKeywordGroups($0) }
                )
            )

            if !collapsed {
                keywordRows(ids: topLevel, depth: 1, tree: tree)
            }
        }
    }

    // MARK: Keyword rows (outline)

    @ViewBuilder
    private func keywordRows(ids: [Int64], depth: Int, tree: KeywordTree) -> some View {
        ForEach(ids, id: \.self) { id in
            AnyView(keywordRow(id, depth: depth, tree: tree))
        }
    }

    @ViewBuilder
    private func keywordRow(_ id: Int64, depth: Int, tree: KeywordTree) -> some View {
        let children = tree.children(of: id)
        let collapsed = collapsedKeywords.contains(id)

        HStack(spacing: 6) {
            if children.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .opacity(0)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        if collapsed {
                            collapsedKeywords.remove(id)
                        } else {
                            collapsedKeywords.insert(id)
                        }
                    }
            }
            Text(tree.node(id)?.name ?? "")
            Spacer()
        }
        .padding(.leading, CGFloat(depth) * 18)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRename(id, tree: tree) }
        .contextMenu {
            Button("Rename") { beginRename(id, tree: tree) }
            Button("Add Sub-keyword") {
                addKeyword(parentId: id, groupId: nil, base: "NEW SUB-KEYWORD")
            }
            Button("Delete", role: .destructive) { pendingKeywordDeletion = id }
        }

        if !collapsed && !children.isEmpty {
            keywordRows(ids: children, depth: depth + 1, tree: tree)
        }
    }

    // MARK: Actions

    /// New nodes are created immediately, then the rename dialog opens —
    /// cancelling keeps the placeholder node (spec §8.6 quirk).
    private func addKeyword(parentId: Int64?, groupId: Int64?, base: String) {
        guard let id = controller.createKeyword(baseName: base, parentId: parentId, groupId: groupId)
        else { return }
        if let parentId { collapsedKeywords.remove(parentId) }
        beginRename(id, tree: controller.snapshot?.keywordTree)
    }

    private func beginRename(_ id: Int64, tree: KeywordTree?) {
        renameText = tree?.node(id)?.name ?? ""
        renameKeywordId = id
    }

    private func palettePicker(selected: String, choose: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(keywordGroupPalette, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(width: 22, height: 22)
                    .overlay {
                        if hex.caseInsensitiveCompare(selected) == .orderedSame {
                            Circle().strokeBorder(Color.primary, lineWidth: 2)
                        }
                    }
                    .onTapGesture { choose(hex) }
            }
        }
        .padding(12)
    }
}

// MARK: Group edit sheet (spec §8.6: name field, palette, preview — 300×380)

private struct GroupEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: KeywordGroupRecord
    let save: (String, String) -> Void

    @State private var name = ""
    @State private var color = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Group")
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onChange(of: name) { _, newValue in
                    let upper = newValue.uppercased()
                    if upper != newValue { name = upper }
                }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 5), spacing: 10) {
                ForEach(keywordGroupPalette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 26, height: 26)
                        .overlay {
                            if hex.caseInsensitiveCompare(color) == .orderedSame {
                                Circle().strokeBorder(Color.primary, lineWidth: 2)
                            }
                        }
                        .onTapGesture { color = hex }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: color) ?? .gray)
                    .frame(width: 14, height: 14)
                Text(name.isEmpty ? "PREVIEW" : name)
                    .fontWeight(.bold)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    save(name, color)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300, height: 380)
        .onAppear {
            name = group.name
            color = group.color
        }
    }
}
