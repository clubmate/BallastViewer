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
            guard oldValue != collapsedGroups else { return }
            controller.setCollapsedGroups(collapsedGroups)
        }
    }

    /// Non-nil presents the rule editor sheet with a *copy* (spec §9.7).
    var editingCollection: CollectionDraft?
    /// Pending destructive actions awaiting their U7 confirmation.
    var pendingGroupDeletion: SmartGroupRecord?
    var pendingCollectionDeletion: SmartCollectionRecord?
    /// Non-nil presents the name prompt for a new group / new collection.
    var namePrompt: NamePrompt?

    struct NamePrompt: Identifiable {
        enum Target { case newGroup, newCollection(groupId: Int64), renameGroup(id: Int64) }
        let target: Target
        var name: String = ""
        var id: String {
            switch target {
            case .newGroup: "newGroup"
            case .newCollection(let groupId): "newCollection:\(groupId)"
            case .renameGroup(let id): "renameGroup:\(id)"
            }
        }
        var title: String {
            switch target {
            case .newGroup: "New Group"
            case .newCollection: "New Smart Collection"
            case .renameGroup: "Rename Group"
            }
        }
    }

    @ObservationIgnored private var store = CollectionCountsStore()

    init(controller: LibraryController) {
        self.controller = controller
        controller.addCatalogObserver { [weak self] event in
            self?.handle(event)
        }
        collapsedGroups = controller.storedCollapsedGroups
        rebuildCounts()
    }

    // MARK: Snapshot accessors for the view

    var groups: [SmartGroupRecord] {
        controller.snapshot?.smartGroups ?? []
    }

    func collections(inGroup groupId: Int64) -> [SmartCollectionRecord] {
        (controller.snapshot?.collections ?? []).filter { $0.groupId == groupId }
    }

    func toggleCollapse(_ groupId: Int64) {
        if collapsedGroups.contains(groupId) {
            collapsedGroups.remove(groupId)
        } else {
            collapsedGroups.insert(groupId)
        }
    }

    // MARK: Counts

    private func handle(_ event: CatalogEvent) {
        switch event {
        case .catalogReplaced, .collectionsChanged:
            if case .catalogReplaced = event {
                collapsedGroups = controller.storedCollapsedGroups
            }
            rebuildCounts()
        case .photosUpdated(let ids):
            guard let snapshot = controller.snapshot else { return }
            // Delta only — O(changed × collections), the acceptance criterion.
            store.update(
                changedPhotos: ids.compactMap { controller.photo(withId: $0) },
                collections: snapshot.collections,
                rulesByCollection: snapshot.rulesByCollection,
                lastImportBatchId: snapshot.meta.lastImportBatchId,
                facts: { photo in
                    photo.id.map { snapshot.queryFacts(forPhotoId: $0) } ?? PhotoQueryFacts()
                }
            )
            counts = store.counts
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
            rulesByCollection: snapshot.rulesByCollection,
            lastImportBatchId: snapshot.meta.lastImportBatchId,
            facts: { photo in
                photo.id.map { snapshot.queryFacts(forPhotoId: $0) } ?? PhotoQueryFacts()
            }
        )
        counts = store.counts
    }

    // MARK: Editing

    func beginEditing(_ collection: SmartCollectionRecord) {
        guard let id = collection.id else { return }
        let rules = (controller.snapshot?.rules ?? [])
            .filter { $0.collectionId == id }
            .sorted { $0.sortOrder < $1.sortOrder }
        editingCollection = CollectionDraft(collection: collection, rules: rules)
    }
}

/// The editor sheet's working copy — Cancel discards it, Save writes it back
/// wholesale (spec §9.7).
struct CollectionDraft: Identifiable {
    var collection: SmartCollectionRecord
    var rules: [DraftRule]
    var id: Int64 { collection.id ?? 0 }

    struct DraftRule: Identifiable, Hashable {
        let id = UUID()
        var type: RuleType
        var operation: RuleOperator
        var value: String
    }

    init(collection: SmartCollectionRecord, rules: [CollectionRuleRecord]) {
        self.collection = collection
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
