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
        // A new group is empty — no membership changed anywhere.
        mutateSnapshot { $0.smartGroups.append(created) }
        emitCatalogEvent(.collectionListChanged)
    }

    func renameSmartGroup(_ id: Int64, to name: String) {
        guard writeSync({ db in try CollectionDAO.renameGroup(id, to: name, in: db) }) != nil
        else { return }
        mutateSnapshot { snapshot in
            if let index = snapshot.smartGroups.firstIndex(where: { $0.id == id }) {
                snapshot.smartGroups[index].name = name
            }
        }
        emitCatalogEvent(.collectionListChanged)
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
        emitCatalogEvent(.collectionListChanged)
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

    /// The editor sheet saves what it edits: name, match mode and the full
    /// rule list (spec §9.7). Group and sort position come from the LIVE
    /// record — the sheet's copy is as old as the sheet, and a reorder or move
    /// made while it was open must not be undone by Save.
    func saveCollection(
        _ collection: SmartCollectionRecord,
        rules: [(type: String, operation: String, value: String)]
    ) {
        guard let collectionId = collection.id,
              var record = snapshot?.collections.first(where: { $0.id == collectionId })
        else { return }
        record.name = collection.name
        record.matchAll = collection.matchAll
        guard writeSync({ (db) -> Void in
            try CollectionDAO.updateCollection(record, in: db)
            try CollectionDAO.saveRules(rules, forCollection: collectionId, in: db)
        }) != nil else { return }
        mutateSnapshot { snapshot in
            if let index = snapshot.collections.firstIndex(where: { $0.id == collectionId }) {
                snapshot.collections[index] = record
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
        let encoded = item.encoded
        mutateSnapshot { $0.meta.selectedCollection = encoded }
        persistMeta(column: "selectedCollection", value: encoded)
    }

    var storedSidebarItem: SidebarItem? {
        snapshot?.meta.selectedCollection.flatMap(SidebarItem.init(encoded:))
    }

    func setCollapsedGroups(_ ids: Set<Int64>) {
        guard let data = try? JSONEncoder().encode(ids.sorted()),
              let json = String(data: data, encoding: .utf8)
        else { return }
        mutateSnapshot { $0.meta.collapsedGroups = json }
        persistMeta(column: "collapsedGroups", value: json)
    }

    var storedCollapsedGroups: Set<Int64> {
        guard let data = snapshot?.meta.collapsedGroups.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int64].self, from: data)
        else { return [] }
        return Set(ids)
    }

    /// Meta writes ride the write pipeline: ordered against every other write,
    /// drained on quit, and never racing a pool that is closing. Only the
    /// changed column is written — persisting the whole in-memory row let a
    /// sidebar click queued during an import commit a stale
    /// `lastImportBatchId` on top of the batch the import had just recorded.
    /// Internal so the library-rename path (+Import) can use the same lane.
    func persistMeta(column: String, value: String?) {
        guard let metaId = snapshot?.meta.id else { return }
        persist { db in
            try LibraryMetaRecord.filter(key: metaId).updateAll(db, Column(column).set(to: value))
        }
    }

    /// Synchronous write for rare structural edits; failures surface as the
    /// app-wide alert and the memory mirror is left untouched. Flushes the
    /// write pipeline first so this commit can never overtake a queued
    /// write-through job (e.g. a keyword-subtree delete overtaking the insert
    /// of an assignment to that very keyword).
    ///
    /// Refused while `isBusy`: the flush barrier would then park the main
    /// thread behind a bulk transaction (import, metadata load, folder undo)
    /// for seconds. The modal shield covers the main window, but not the
    /// Inspector keyword field or the Settings editors — this is the backstop.
    func writeSync<T>(_ body: (Database) throws -> T) -> T? {
        guard let library else { return nil }
        guard !isBusy else {
            errorMessage = Self.busyMessage
            return nil
        }
        writePipeline?.flushSync()
        do {
            return try library.pool.write(body)
        } catch {
            errorMessage = "Could not save changes to the library.\n\(error.localizedDescription)"
            return nil
        }
    }
}
