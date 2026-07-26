import BallastCore
import Foundation
import GRDB

/// Smart-group / collection management. Structural edits are rare and tiny, so
/// they write synchronously (WAL, NORMAL sync — no per-commit fsync) and then
/// mirror the result into the snapshot; every change emits `.collectionsChanged`.
extension LibraryController {
    // MARK: Groups

    func createSmartGroup(named name: String) {
        guard let created: SmartGroupRecord = writeSync({ db in
            try CollectionDAO.createGroup(name: name, in: db)
        }) else { return }
        mutateSnapshot { $0.smartGroups.append(created) }
        emitCatalogEvent(.collectionsChanged)
    }

    func renameSmartGroup(_ id: Int64, to name: String) {
        guard writeSync({ db in try CollectionDAO.renameGroup(id, to: name, in: db) }) != nil
        else { return }
        mutateSnapshot { snapshot in
            if let index = snapshot.smartGroups.firstIndex(where: { $0.id == id }) {
                snapshot.smartGroups[index].name = name
            }
        }
        emitCatalogEvent(.collectionsChanged)
    }

    /// Deletes the group with its collections and rules (FK cascade). The U7
    /// confirmation happens in the UI before this is called.
    func deleteSmartGroup(_ id: Int64) {
        guard writeSync({ db in try CollectionDAO.deleteGroup(id, in: db) }) != nil else { return }
        mutateSnapshot { snapshot in
            let removed = Set(snapshot.collections.filter { $0.groupId == id }.compactMap(\.id))
            snapshot.smartGroups.removeAll { $0.id == id }
            snapshot.collections.removeAll { $0.groupId == id }
            snapshot.rules.removeAll { removed.contains($0.collectionId) }
        }
        emitCatalogEvent(.collectionsChanged)
    }

    func reorderSmartGroups(_ orderedIds: [Int64]) {
        guard writeSync({ db in try CollectionDAO.reorderGroups(orderedIds, in: db) }) != nil
        else { return }
        mutateSnapshot { snapshot in
            for (index, id) in orderedIds.enumerated() {
                if let position = snapshot.smartGroups.firstIndex(where: { $0.id == id }) {
                    snapshot.smartGroups[position].sortOrder = index
                }
            }
            snapshot.smartGroups.sort { $0.sortOrder < $1.sortOrder }
        }
        emitCatalogEvent(.collectionsChanged)
    }

    // MARK: Collections

    /// New collections start with no rules and matchAll — showing the whole
    /// library until narrowed down (Q6). Returns the id for auto-selection.
    @discardableResult
    func createCollection(named name: String, inGroup groupId: Int64) -> Int64? {
        guard let created: SmartCollectionRecord = writeSync({ db in
            try CollectionDAO.createCollection(name: name, inGroup: groupId, in: db)
        }) else { return nil }
        mutateSnapshot { $0.collections.append(created) }
        emitCatalogEvent(.collectionsChanged)
        return created.id
    }

    func deleteCollection(_ id: Int64) {
        guard writeSync({ db in try CollectionDAO.deleteCollection(id, in: db) }) != nil
        else { return }
        mutateSnapshot { snapshot in
            snapshot.collections.removeAll { $0.id == id }
            snapshot.rules.removeAll { $0.collectionId == id }
        }
        emitCatalogEvent(.collectionsChanged)
    }

    func reorderCollections(_ orderedIds: [Int64], inGroup groupId: Int64) {
        guard writeSync({ db in
            try CollectionDAO.reorderCollections(orderedIds, inGroup: groupId, in: db)
        }) != nil else { return }
        mutateSnapshot { snapshot in
            for (index, id) in orderedIds.enumerated() {
                if let position = snapshot.collections.firstIndex(where: { $0.id == id }) {
                    snapshot.collections[position].sortOrder = index
                    snapshot.collections[position].groupId = groupId
                }
            }
            snapshot.collections.sort { ($0.groupId, $0.sortOrder) < ($1.groupId, $1.sortOrder) }
        }
        emitCatalogEvent(.collectionsChanged)
    }

    /// The editor sheet saves its copy wholesale: name, match mode and the
    /// full rule list (spec §9.7).
    func saveCollection(
        _ collection: SmartCollectionRecord,
        rules: [(type: String, operation: String, value: String)]
    ) {
        guard let collectionId = collection.id else { return }
        guard writeSync({ (db) -> Void in
            try CollectionDAO.updateCollection(collection, in: db)
            try CollectionDAO.saveRules(rules, forCollection: collectionId, in: db)
        }) != nil else { return }
        mutateSnapshot { snapshot in
            if let index = snapshot.collections.firstIndex(where: { $0.id == collectionId }) {
                snapshot.collections[index] = collection
            }
            snapshot.rules.removeAll { $0.collectionId == collectionId }
            // Ids of the replaced rule rows are not mirrored back — nothing
            // keys off rule ids, they are an ordered value list per collection.
            snapshot.rules.append(contentsOf: rules.enumerated().map { index, rule in
                CollectionRuleRecord(
                    collectionId: collectionId,
                    type: rule.type, operation: rule.operation, value: rule.value,
                    sortOrder: index
                )
            })
        }
        emitCatalogEvent(.collectionsChanged)
    }

    // MARK: Per-library UI state (libraryMeta)

    /// Persists the sidebar selection — it survives relaunch (Q24).
    func setSelectedSidebarItem(_ item: SidebarItem) {
        mutateSnapshot { $0.meta.selectedCollection = item.encoded }
        persistMeta()
    }

    var storedSidebarItem: SidebarItem? {
        snapshot?.meta.selectedCollection.flatMap(SidebarItem.init(encoded:))
    }

    func setCollapsedGroups(_ ids: Set<Int64>) {
        guard let data = try? JSONEncoder().encode(ids.sorted()),
              let json = String(data: data, encoding: .utf8)
        else { return }
        mutateSnapshot { $0.meta.collapsedGroups = json }
        persistMeta()
    }

    var storedCollapsedGroups: Set<Int64> {
        guard let data = snapshot?.meta.collapsedGroups.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int64].self, from: data)
        else { return [] }
        return Set(ids)
    }

    private func persistMeta() {
        guard let library, let meta = snapshot?.meta else { return }
        Task {
            do {
                try await library.pool.write { db in try meta.update(db) }
            } catch {
                errorMessage = "Could not save library state.\n\(error.localizedDescription)"
            }
        }
    }

    /// Synchronous write for rare structural edits; failures surface as the
    /// app-wide alert and the memory mirror is left untouched.
    func writeSync<T>(_ body: (Database) throws -> T) -> T? {
        guard let library else { return nil }
        do {
            return try library.pool.write(body)
        } catch {
            errorMessage = "Could not save changes to the library.\n\(error.localizedDescription)"
            return nil
        }
    }
}
