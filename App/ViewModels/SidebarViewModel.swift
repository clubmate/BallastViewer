import BallastCore
import Foundation
import Observation

/// State behind the left panel: live badge counts (incremental via
/// `CollectionCountsStore`), group collapse (persisted per library), and the
/// transient edit/delete/create states the sidebar UI presents.
@MainActor @Observable
final class SidebarViewModel {
    @ObservationIgnored private unowned let controller: LibraryController

    private(set) var counts = SidebarCounts()
    var collapsedGroups: Set<Int64> = [] {
        didSet {
            guard oldValue != collapsedGroups, !isRestoringCollapsedGroups else { return }
            controller.setCollapsedGroups(collapsedGroups)
        }
    }
    /// Set while `collapsedGroups` is loaded FROM the library: a restore is
    /// not a user edit and must not be written back (the DB already holds
    /// it; persisting from `.catalogReplaced` would also race the reload).
    @ObservationIgnored private var isRestoringCollapsedGroups = false

    private func restoreCollapsedGroups() {
        isRestoringCollapsedGroups = true
        defer { isRestoringCollapsedGroups = false }
        collapsedGroups = controller.storedCollapsedGroups
    }

    /// Non-nil presents the rule editor sheet with a *copy* (spec §9.7).
    var editingCollection: CollectionDraft?
    /// Pending destructive actions awaiting their U7 confirmation.
    var pendingGroupDeletion: SmartGroupRecord?
    var pendingCollectionDeletion: SmartCollectionRecord?
    /// Non-nil presents the name prompt for a new group / new collection.
    var namePrompt: NamePrompt?

    struct NamePrompt: Identifiable {
        enum Target {
            case newGroup
            /// `parentId` non-nil = child collection under that parent (U41).
            case newCollection(groupId: Int64, parentId: Int64?)
            case renameGroup(id: Int64)
        }
        let target: Target
        var name: String = ""
        var id: String {
            switch target {
            case .newGroup: "newGroup"
            case .newCollection(let groupId, let parentId):
                "newCollection:\(groupId):\(parentId.map(String.init) ?? "-")"
            case .renameGroup(let id): "renameGroup:\(id)"
            }
        }
        var title: String {
            switch target {
            case .newGroup: "New Group"
            case .newCollection(_, let parentId):
                parentId == nil ? "New Smart Collection" : "New Child Collection"
            case .renameGroup: "Rename Group"
            }
        }
    }

    /// Holds the compiled collection rules from the last rebuild, so a
    /// photosUpdated delta never regroups or recompiles anything.
    @ObservationIgnored private var store = CollectionCountsStore()

    init(controller: LibraryController) {
        self.controller = controller
        controller.addCatalogObserver { [weak self] event in
            self?.handle(event)
        }
        restoreCollapsedGroups()
        refreshLists()
        rebuildCounts()
    }

    // MARK: Snapshot accessors for the view

    /// Own copies rather than reads through `controller.snapshot`: the
    /// controller mutates that observable in place for every rating,
    /// rotation and keyword change, which would re-render the whole sidebar
    /// per key press. These refresh only on collection-list events.
    private(set) var groups: [SmartGroupRecord] = []
    /// FLAT per group, children included — the group-deletion blast radius.
    private(set) var collectionsByGroup: [Int64: [SmartCollectionRecord]] = [:]
    /// U41: disclosure state of collections with children. Transient by
    /// design — like the keyword editor's outline, unlike group collapse.
    var collapsedCollections: Set<Int64> = []

    func collections(inGroup groupId: Int64) -> [SmartCollectionRecord] {
        collectionsByGroup[groupId] ?? []
    }

    /// One visible outline row (U41): the collection, its indent depth and
    /// whether it can disclose children.
    struct CollectionRow: Identifiable {
        let collection: SmartCollectionRecord
        let depth: Int
        let hasChildren: Bool
        var id: Int64 { collection.id ?? 0 }
    }

    /// Depth-first flattening of a group's visible collection outline —
    /// alphabetical per level (U32), collapsed subtrees skipped.
    func collectionRows(inGroup groupId: Int64) -> [CollectionRow] {
        let childrenByParent = Dictionary(
            grouping: collections(inGroup: groupId).filter { $0.parentId != nil },
            by: { $0.parentId! }
        )
        func sorted(_ list: [SmartCollectionRecord]) -> [SmartCollectionRecord] {
            list.sorted { CaseInsensitiveMatch.fold($0.name) < CaseInsensitiveMatch.fold($1.name) }
        }
        var rows: [CollectionRow] = []
        var stack: [(SmartCollectionRecord, Int)] = sorted(
            collections(inGroup: groupId).filter { $0.parentId == nil }
        ).reversed().map { ($0, 0) }
        while let (collection, depth) = stack.popLast() {
            guard let id = collection.id else { continue }
            let children = childrenByParent[id] ?? []
            rows.append(CollectionRow(
                collection: collection, depth: depth, hasChildren: !children.isEmpty
            ))
            if !children.isEmpty, !collapsedCollections.contains(id) {
                stack.append(contentsOf: sorted(children).reversed().map { ($0, depth + 1) })
            }
        }
        return rows
    }

    private func refreshLists() {
        let snapshot = controller.snapshot
        let newGroups = snapshot?.smartGroups ?? []
        let newByGroup = Dictionary(grouping: snapshot?.collections ?? [], by: \.groupId)
        if groups != newGroups { groups = newGroups }
        if collectionsByGroup != newByGroup { collectionsByGroup = newByGroup }
    }

    func toggleCollapse(_ groupId: Int64) {
        if collapsedGroups.contains(groupId) {
            collapsedGroups.remove(groupId)
        } else {
            collapsedGroups.insert(groupId)
        }
    }

    func toggleCollectionCollapse(_ id: Int64) {
        if collapsedCollections.contains(id) {
            collapsedCollections.remove(id)
        } else {
            collapsedCollections.insert(id)
        }
    }

    // MARK: Counts

    private func handle(_ event: CatalogEvent) {
        switch event {
        case .catalogReplaced, .collectionsChanged:
            if case .catalogReplaced = event {
                restoreCollapsedGroups()
            }
            refreshLists()
            rebuildCounts()
        case .collectionListChanged:
            // Cosmetic (rename/reorder/empty group): membership is untouched,
            // so no O(photos × collections) sweep — only the row lists.
            refreshLists()
        case .photosUpdated(let ids):
            guard let snapshot = controller.snapshot else { return }
            // Delta only — O(changed × collections), the acceptance criterion.
            store.update(
                changedPhotos: ids.compactMap { controller.photo(withId: $0) },
                lastImportBatchId: snapshot.meta.lastImportBatchId,
                facts: { [controller] photo in controller.queryFacts(for: photo) }
            )
            // Equality guard: a rotation changes no count, and an unguarded
            // assignment would invalidate the sidebar per key repeat.
            if counts != store.counts { counts = store.counts }
        }
    }

    private func rebuildCounts() {
        guard let snapshot = controller.snapshot else {
            store = CollectionCountsStore()
            counts = SidebarCounts()
            return
        }
        store.rebuild(
            photos: snapshot.photos,
            collections: snapshot.collections,
            rulesByCollection: snapshot.makeRulesByCollection(),
            lastImportBatchId: snapshot.meta.lastImportBatchId,
            facts: { [controller] photo in controller.queryFacts(for: photo) }
        )
        if counts != store.counts { counts = store.counts }
    }

    // MARK: Editing

    func beginEditing(_ collection: SmartCollectionRecord) {
        guard let id = collection.id else { return }
        let allRules = controller.snapshot?.rules ?? []
        let rules = allRules
            .filter { $0.collectionId == id }
            .sorted { $0.sortOrder < $1.sortOrder }
        // U41: ancestors' rules show greyed out in the editor — root first,
        // so the list reads top-down like the sidebar outline.
        let allCollections = controller.snapshot?.collections ?? []
        let inherited = CollectionHierarchy.ancestors(of: id, in: allCollections)
            .reversed()
            .flatMap { ancestor in
                allRules
                    .filter { $0.collectionId == ancestor.id }
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map { CollectionDraft.InheritedRule(originName: ancestor.name, record: $0) }
            }
        editingCollection = CollectionDraft(
            collection: collection,
            rules: rules,
            inheritedRules: inherited,
            childCount: CollectionHierarchy.descendantIds(of: id, in: allCollections).count
        )
    }
}

/// The editor sheet's working copy — Cancel discards it, Save writes it back
/// wholesale (spec §9.7).
struct CollectionDraft: Identifiable {
    var collection: SmartCollectionRecord
    var rules: [DraftRule]
    /// U41: the ancestors' rules, root first — displayed greyed out and
    /// read-only; Save never touches them.
    let inheritedRules: [InheritedRule]
    /// U41: how many descendants an edit propagates into (editor hint).
    let childCount: Int
    var id: Int64 { collection.id ?? 0 }

    struct DraftRule: Identifiable, Hashable {
        let id = UUID()
        var type: RuleType
        var operation: RuleOperator
        var value: String
    }

    struct InheritedRule: Identifiable, Hashable {
        let id = UUID()
        let originName: String
        let record: CollectionRuleRecord
    }

    init(
        collection: SmartCollectionRecord,
        rules: [CollectionRuleRecord],
        inheritedRules: [InheritedRule] = [],
        childCount: Int = 0
    ) {
        self.collection = collection
        self.inheritedRules = inheritedRules
        self.childCount = childCount
        // Unknown types/operators exist only in libraries written by newer
        // versions (D6); the editor cannot represent them, so editing drops
        // them on save — matching wholesale-replace semantics.
        self.rules = rules.compactMap { record in
            guard let type = RuleType(rawValue: record.type),
                  let operation = RuleOperator(rawValue: record.operation)
            else { return nil }
            return DraftRule(type: type, operation: operation, value: record.value)
        }
    }
}
