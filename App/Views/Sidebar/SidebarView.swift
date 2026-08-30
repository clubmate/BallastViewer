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

    /// One reorder session per id list (group ids and collection ids can
    /// collide numerically).
    @State private var groupReorder = RowReorderSession()
    @State private var collectionReorder = RowReorderSession()

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
                        flush: {
                            groupReorder.flush()
                            collectionReorder.flush()
                        },
                        end: {
                            groupReorder.end()
                            collectionReorder.end()
                        }
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
            // Collapsing hides the + button too (Q25). An unsaved group
            // (nil id) cannot parent a collection — no button rather than a
            // bogus -1 parent.
            if !collapsed, let parentId = group.id {
                Button {
                    sidebar.namePrompt = .init(target: .newCollection(groupId: parentId))
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                // Optically centred under the count badges in the rows below —
                // flush-right the glyph sat visibly right of the badge pills.
                .padding(.trailing, 4)
                .help("New Smart Collection")
            }
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
            ForEach(collectionReorder.ordered(sidebar.collections(inGroup: groupId), id: \.id)) { collection in
                collectionRow(collection, inGroup: groupId)
            }
        }
    }

    @ViewBuilder
    private func collectionRow(_ collection: SmartCollectionRecord, inGroup groupId: Int64) -> some View {
        if let collectionId = collection.id {
            row(
                item: .collection(collectionId),
                count: sidebar.counts.collections[collectionId]
            ) {
                Text(collection.name)
            }
            // Simultaneous: the row is a Button, which would otherwise swallow
            // the second click of a double-click.
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { sidebar.beginEditing(collection) }
            )
            .contextMenu {
                Button("Edit Smart Collection") { sidebar.beginEditing(collection) }
                Button("Delete", role: .destructive) {
                    sidebar.pendingCollectionDeletion = collection
                }
            }
            .onDrag {
                collectionReorder.begin(
                    draggedId: collectionId,
                    order: sidebar.collections(inGroup: groupId).compactMap(\.id),
                    commit: { controller.reorderCollections($0, inGroup: groupId) }
                )
                return NSItemProvider(object: "collection:\(collectionId)" as NSString)
            }
            .onDrop(
                of: [UTType.plainText],
                delegate: RowReorderDelegate(targetId: collectionId, session: collectionReorder)
            )
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
                    case .newCollection(let groupId):
                        // Auto-select the new collection (spec §7.7) — it has
                        // no rules yet, so it shows the whole library (Q6).
                        if let id = controller.createCollection(named: name, inGroup: groupId) {
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
                Text("Delete “\(collection.name)”? Photos are not affected.")
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
