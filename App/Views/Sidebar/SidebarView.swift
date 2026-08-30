import BallastCore
import SwiftUI
import UniformTypeIdentifiers

/// Left panel (spec §9.2): LIBRARY header, ALL PHOTOS, LAST IMPORT, star rows
/// ★★★★★…★, then the user groups with their collections, and a new-group
/// footer. Selection = accent background; counts as pill badges.
struct SidebarView: View {
    @Environment(LibraryController.self) private var controller
    let sidebar: SidebarViewModel
    let center: CenterViewModel

    /// Groups are drag-ordered; collections inside a group list
    /// alphabetically (U32) and are not draggable.
    @State private var groupReorder = RowReorderSession()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Text("LIBRARY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                    row(item: .allPhotos, count: sidebar.counts.allPhotos) {
                        Text("ALL PHOTOS")
                    }
                    row(item: .lastImport, count: sidebar.counts.lastImport) {
                        Text("LAST IMPORT")
                    }
                    // Descending ★★★★★ → ★ (spec §9.2); exact-match rows (Q9).
                    ForEach((1...5).reversed(), id: \.self) { stars in
                        row(item: .rating(stars), count: sidebar.counts.ratings[stars]) {
                            HStack(spacing: 1) {
                                ForEach(0..<stars, id: \.self) { _ in
                                    Image(systemName: "star.fill").font(.caption2)
                                }
                            }
                        }
                    }
                    // UNRATED below ★: exact rating 0 (U28).
                    row(item: .rating(0), count: sidebar.counts.ratings[0]) {
                        Image(systemName: "star.slash").font(.caption2)
                    }

                    ForEach(groupReorder.ordered(sidebar.groups, id: \.id)) { group in
                        groupBlock(group)
                    }
                }
                .padding(.vertical, 4)
                // Drops between rows (and drags that leave the list) end the
                // reorder session — one write per drag.
                .onDrop(
                    of: [UTType.plainText],
                    delegate: RowReorderEndDelegate(
                        flush: { groupReorder.flush() },
                        end: { groupReorder.end() }
                    )
                )
            }

            FileWriteStatusSection()
            Divider()
            HStack {
                Button {
                    sidebar.namePrompt = .init(target: .newGroup)
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("New Group")
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: PanelMetrics.footerHeight)
        }
        .sidebarPrompts(sidebar: sidebar, center: center, controller: controller)
    }

    // MARK: Rows

    private func row(
        item: SidebarItem, count: Int?, @ViewBuilder label: () -> some View
    ) -> some View {
        let selected = center.activeItem == item
        return Button {
            center.selectSidebarItem(item)
        } label: {
            rowLabel(selected: selected, count: count, label: label)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func rowLabel(
        selected: Bool, count: Int?, @ViewBuilder label: () -> some View
    ) -> some View {
        HStack {
            label()
            Spacer()
            if let count {
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
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(selected ? Color.accentColor : .clear)
    }

    // MARK: Groups

    @ViewBuilder
    private func groupBlock(_ group: SmartGroupRecord) -> some View {
        let groupId = group.id ?? -1
        let collapsed = sidebar.collapsedGroups.contains(groupId)

        HStack {
            Text(group.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 26)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                sidebar.toggleCollapse(groupId)
            }
        }
        .contextMenu {
            // U41: creation lives in the context menu — top-level here, child
            // collections on their parent's row (the group "+" is gone).
            if let parentId = group.id {
                Button("New Smart Collection") {
                    sidebar.namePrompt = .init(target: .newCollection(groupId: parentId, parentId: nil))
                }
            }
            Button("Rename Group") {
                sidebar.namePrompt = .init(target: .renameGroup(id: groupId), name: group.name)
            }
            Button("Delete Group", role: .destructive) {
                sidebar.pendingGroupDeletion = group
            }
        }
        .onDrag {
            groupReorder.begin(
                draggedId: groupId,
                order: sidebar.groups.compactMap(\.id),
                commit: { controller.reorderSmartGroups($0) }
            )
            return NSItemProvider(object: "group:\(groupId)" as NSString)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: RowReorderDelegate(targetId: groupId, session: groupReorder)
        )

        if !collapsed {
            // U41: outline rows — depth-indented, disclosure chevron on
            // collections with children.
            ForEach(sidebar.collectionRows(inGroup: groupId)) { outlineRow in
                collectionRow(outlineRow)
            }
        }
    }

    @ViewBuilder
    private func collectionRow(_ outlineRow: SidebarViewModel.CollectionRow) -> some View {
        let collection = outlineRow.collection
        if let collectionId = collection.id {
            let collapsed = sidebar.collapsedCollections.contains(collectionId)
            row(
                item: .collection(collectionId),
                count: sidebar.counts.collections[collectionId]
            ) {
                HStack(spacing: 4) {
                    if outlineRow.hasChildren {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                            .foregroundStyle(.secondary)
                            // The chevron toggles disclosure WITHOUT selecting
                            // the row — high priority beats the row button.
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    sidebar.toggleCollectionCollapse(collectionId)
                                }
                            })
                    }
                    Text(collection.name)
                }
                .padding(.leading, CGFloat(outlineRow.depth) * 14)
            }
            // Simultaneous: the row is a Button, which would otherwise swallow
            // the second click of a double-click.
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { sidebar.beginEditing(collection) }
            )
            .contextMenu {
                Button("Edit Smart Collection") { sidebar.beginEditing(collection) }
                // U41: a child inherits this collection's (and its ancestors')
                // rules; it is created in the parent's group.
                Button("New Child Collection") {
                    sidebar.namePrompt = .init(
                        target: .newCollection(groupId: collection.groupId, parentId: collectionId)
                    )
                }
                Button("Delete", role: .destructive) {
                    sidebar.pendingCollectionDeletion = collection
                }
            }
        }
    }
}

// MARK: Prompts & confirmations

private extension View {
    /// Name prompts (new group / new collection / rename) and the U7
    /// delete confirmations, attached once to the sidebar.
    func sidebarPrompts(
        sidebar: SidebarViewModel, center: CenterViewModel, controller: LibraryController
    ) -> some View {
        @Bindable var sidebar = sidebar
        return self
            .alert(
                sidebar.namePrompt?.title ?? "",
                isPresented: Binding(
                    get: { sidebar.namePrompt != nil },
                    set: { if !$0 { sidebar.namePrompt = nil } }
                )
            ) {
                TextField("Name", text: Binding(
                    get: { sidebar.namePrompt?.name ?? "" },
                    set: { sidebar.namePrompt?.name = $0 }
                ))
                Button("OK") {
                    guard let prompt = sidebar.namePrompt else { return }
                    sidebar.namePrompt = nil
                    let name = prompt.name.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    switch prompt.target {
                    case .newGroup:
                        controller.createSmartGroup(named: name)
                    case .newCollection(let groupId, let parentId):
                        // Auto-select the new collection (spec §7.7) — with
                        // no rules yet it shows the whole library (Q6), or
                        // exactly the parent's result for a child (U41).
                        if let id = controller.createCollection(
                            named: name, inGroup: groupId, parentId: parentId
                        ) {
                            // A child must be visible right away.
                            if let parentId { sidebar.collapsedCollections.remove(parentId) }
                            center.selectSidebarItem(.collection(id))
                        }
                    case .renameGroup(let id):
                        controller.renameSmartGroup(id, to: name)
                    }
                }
                Button("Cancel", role: .cancel) { sidebar.namePrompt = nil }
            }
            .alert(
                "Delete Group",
                isPresented: Binding(
                    get: { sidebar.pendingGroupDeletion != nil },
                    set: { if !$0 { sidebar.pendingGroupDeletion = nil } }
                ),
                presenting: sidebar.pendingGroupDeletion
            ) { group in
                Button("Delete", role: .destructive) {
                    if let id = group.id { controller.deleteSmartGroup(id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { group in
                let count = group.id.map { sidebar.collections(inGroup: $0).count } ?? 0
                Text("Delete “\(group.name)” and its \(count) smart collection\(count == 1 ? "" : "s")? Photos are not affected.")
            }
            .alert(
                "Delete Smart Collection",
                isPresented: Binding(
                    get: { sidebar.pendingCollectionDeletion != nil },
                    set: { if !$0 { sidebar.pendingCollectionDeletion = nil } }
                ),
                presenting: sidebar.pendingCollectionDeletion
            ) { collection in
                Button("Delete", role: .destructive) {
                    if let id = collection.id { controller.deleteCollection(id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { collection in
                // U41: children go with their parent — say so (U7).
                let childCount = collection.id.map(controller.collectionDescendantCount) ?? 0
                let children = childCount == 0
                    ? ""
                    : " and its \(childCount) child collection\(childCount == 1 ? "" : "s")"
                Text("Delete “\(collection.name)”\(children)? Photos are not affected.")
            }
            .sheet(item: Binding(
                get: { sidebar.editingCollection },
                set: { sidebar.editingCollection = $0 }
            )) { draft in
                CollectionEditorSheet(
                    draft: draft,
                    keywordGroups: controller.vocabulary.groups
                ) { saved in
                    controller.saveCollection(
                        saved.collection,
                        rules: saved.rules.map {
                            ($0.type.rawValue, $0.operation.rawValue, $0.value)
                        }
                    )
                }
            }
    }
}
