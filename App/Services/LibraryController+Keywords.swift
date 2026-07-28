import BallastCore
import Foundation
import GRDB

/// Keyword assignment (spec §8.4) and vocabulary editing (spec §8.6).
///
/// Assignments follow the mutation contract: memory first, async single-row
/// write-through, `.photosUpdated`. Vocabulary edits are rare structural changes
/// and write synchronously (ids and the rebuilt tree are needed immediately);
/// they emit `.photosUpdated` for every carrier photo whenever derived facts
/// (paths, effective groups) change — that is what makes a rename update chips
/// and collection counts everywhere instantly (C4).
extension LibraryController {
    // MARK: Assignment

    /// Resolves typed field text (Q15/Q16) and assigns the keyword to all given
    /// photos (U3 batch semantics). Unmatched text becomes an ad-hoc keyword.
    @discardableResult
    func assignKeyword(text: String, toPhotoIds photoIds: [Int64]) -> Int64? {
        guard !photoIds.isEmpty, let keywordId = resolveOrCreateKeyword(text) else { return nil }
        assignKeyword(id: keywordId, toPhotoIds: photoIds)
        return keywordId
    }

    func assignKeyword(id keywordId: Int64, toPhotoIds photoIds: [Int64]) {
        guard snapshot?.keywordTree.node(keywordId) != nil else { return }
        var changed: [Int64] = []
        mutateSnapshot { snapshot in
            for photoId in photoIds
            where !(snapshot.keywordIdsByPhoto[photoId]?.contains(keywordId) ?? false) {
                snapshot.keywordIdsByPhoto[photoId, default: []].insert(keywordId)
                changed.append(photoId)
            }
        }
        guard !changed.isEmpty else { return }
        let photoIds = changed
        persist { db in try PhotoDAO.assignKeyword(keywordId, toPhotoIds: photoIds, in: db) }
        emitCatalogEvent(.photosUpdated(photoIds))
    }

    func removeKeyword(id keywordId: Int64, fromPhotoIds photoIds: [Int64]) {
        var changed: [Int64] = []
        mutateSnapshot { snapshot in
            for photoId in photoIds
            where snapshot.keywordIdsByPhoto[photoId]?.contains(keywordId) == true {
                snapshot.keywordIdsByPhoto[photoId]?.remove(keywordId)
                changed.append(photoId)
            }
        }
        guard !changed.isEmpty else { return }
        let photoIds = changed
        persist { db in try PhotoDAO.removeKeyword(keywordId, fromPhotoIds: photoIds, in: db) }
        emitCatalogEvent(.photosUpdated(photoIds))
    }

    /// Assigned to every photo → remove from all; otherwise assign to all
    /// (spec §8.4 toggle semantics — keyboard/MIDI bindings land in steps 9/11).
    func toggleKeyword(text: String, forPhotoIds photoIds: [Int64]) {
        guard !photoIds.isEmpty, let snapshot,
              let keywordId = resolveOrCreateKeyword(text) else { return }
        let allHaveIt = photoIds.allSatisfy {
            snapshot.keywordIdsByPhoto[$0]?.contains(keywordId) == true
        }
        if allHaveIt {
            removeKeyword(id: keywordId, fromPhotoIds: photoIds)
        } else {
            assignKeyword(id: keywordId, toPhotoIds: photoIds)
        }
    }

    /// Q16 first-match path resolution; no match creates the components as
    /// ad-hoc nodes (grey). Creation is a sync write — the id is needed now.
    private func resolveOrCreateKeyword(_ text: String) -> Int64? {
        guard let snapshot else { return nil }
        switch KeywordResolver.resolve(text, tree: snapshot.keywordTree) {
        case nil:
            return nil
        case .existing(let id):
            return id
        case .create(let components):
            guard let result: (id: Int64, records: [KeywordRecord]) = writeSync({ db in
                let id = try KeywordDAO.ensurePath(components, groupId: nil, in: db)
                return (id, try KeywordDAO.fetchAll(db))
            }) else { return nil }
            mutateSnapshot { $0.keywordTree = KeywordTree(records: result.records) }
            return result.id
        }
    }

    // MARK: Vocabulary editing (Settings ▸ Keywords)

    /// Creates a node named `baseName` (suffixed for uniqueness among siblings)
    /// and returns its id — the editor opens the rename dialog right after.
    @discardableResult
    func createKeyword(baseName: String, parentId: Int64?, groupId: Int64?) -> Int64? {
        guard let snapshot else { return nil }
        let name = uniqueSiblingName(
            base: KeywordDAO.normalize(baseName), parentId: parentId, tree: snapshot.keywordTree
        )
        guard let result: (id: Int64, records: [KeywordRecord]) = writeSync({ db in
            var record = KeywordRecord(parentId: parentId, groupId: groupId, name: name)
            try record.insert(db)
            return (record.id!, try KeywordDAO.fetchAll(db))
        }) else { return nil }
        mutateSnapshot { $0.keywordTree = KeywordTree(records: result.records) }
        // No photo carries a brand-new node — no event needed.
        return result.id
    }

    /// One UPDATE; every chip/count derived from the subtree's paths follows (C4).
    func renameKeyword(_ id: Int64, to newName: String) {
        guard let snapshot else { return }
        let name = KeywordDAO.normalize(newName)
        guard !name.isEmpty else { return }
        let node = snapshot.keywordTree.node(id)
        guard name != node?.name else { return }
        if siblingExists(named: name, parentId: node?.parentId, excluding: id, tree: snapshot.keywordTree) {
            errorMessage = "A keyword named “\(name)” already exists here."
            return
        }
        guard let records: [KeywordRecord] = writeSync({ db in
            try KeywordDAO.rename(id, to: name, in: db)
            return try KeywordDAO.fetchAll(db)
        }) else { return }
        let carriers = photoIdsCarrying(keywordIds: subtreeIds(of: id))
        mutateSnapshot { $0.keywordTree = KeywordTree(records: records) }
        emitCatalogEvent(.photosUpdated(carriers))
    }

    /// U7 confirmation numbers for the editor's delete alert.
    func keywordDeletionImpact(_ id: Int64) -> (keywordCount: Int, photoCount: Int) {
        let ids = subtreeIds(of: id)
        return (ids.count, photoIdsCarrying(keywordIds: ids).count)
    }

    /// Deletes the node and its subtree including all assignments (spec §8.6).
    func deleteKeywordSubtree(_ id: Int64) {
        guard snapshot != nil else { return }
        let removedIds = subtreeIds(of: id)
        let carriers = photoIdsCarrying(keywordIds: removedIds)
        guard let records: [KeywordRecord] = writeSync({ db in
            try KeywordDAO.deleteSubtree(id, in: db)
            return try KeywordDAO.fetchAll(db)
        }) else { return }
        mutateSnapshot { snapshot in
            snapshot.keywordTree = KeywordTree(records: records)
            for photoId in carriers {
                snapshot.keywordIdsByPhoto[photoId]?.subtract(removedIds)
            }
        }
        emitCatalogEvent(.photosUpdated(carriers))
    }

    // MARK: Groups

    func renameKeywordGroup(_ id: Int64, to newName: String) {
        let name = KeywordDAO.normalize(newName)
        guard !name.isEmpty else { return }
        guard writeSync({ db in try KeywordDAO.renameGroup(id, to: name, in: db) }) != nil
        else { return }
        // Group names are not part of query facts — no photo event needed.
        mutateSnapshot { snapshot in
            if let index = snapshot.keywordGroups.firstIndex(where: { $0.id == id }) {
                snapshot.keywordGroups[index].name = name
            }
        }
    }

    func setKeywordGroupColor(_ id: Int64, color: String) {
        guard writeSync({ db in try KeywordDAO.setGroupColor(id, color: color, in: db) }) != nil
        else { return }
        mutateSnapshot { snapshot in
            if let index = snapshot.keywordGroups.firstIndex(where: { $0.id == id }) {
                snapshot.keywordGroups[index].color = color
            }
        }
    }

    /// Deletion numbers for the U7 alert: member keywords (they become ad-hoc,
    /// C3) and Smart Collection rules that reference the group (they will stop
    /// matching — the spec §8.3 fix asks for this warning).
    func groupDeletionImpact(_ id: Int64) -> (keywordCount: Int, ruleCount: Int) {
        guard let snapshot else { return (0, 0) }
        let members = snapshot.keywordTree.allIdsDepthFirst()
            .filter { snapshot.keywordTree.node($0)?.groupId == id }
        let rules = snapshot.rules.filter {
            RuleType(rawValue: $0.type) == .keywordGroup && $0.value == String(id)
        }
        return (members.count, rules.count)
    }

    /// Members become ad-hoc/grey (groupId NULL via FK cascade, fixes C3).
    func deleteKeywordGroup(_ id: Int64) {
        guard let snapshot else { return }
        // Effective groups change for every photo carrying a member — compute first.
        let memberIds = Set(snapshot.keywordTree.allIdsDepthFirst().filter {
            snapshot.keywordTree.effectiveGroupId(of: $0) == id
        })
        let carriers = photoIdsCarrying(keywordIds: memberIds)
        guard let records: [KeywordRecord] = writeSync({ db in
            try KeywordDAO.deleteGroup(id, in: db)
            return try KeywordDAO.fetchAll(db)
        }) else { return }
        mutateSnapshot { snapshot in
            snapshot.keywordGroups.removeAll { $0.id == id }
            snapshot.keywordTree = KeywordTree(records: records)
        }
        emitCatalogEvent(.photosUpdated(carriers))
    }

    /// Persists a drag reorder (Q18: the order drives chip sort priority).
    func reorderKeywordGroups(_ orderedIds: [Int64]) {
        guard writeSync({ db in try KeywordDAO.reorderGroups(orderedIds, in: db) }) != nil
        else { return }
        mutateSnapshot { snapshot in
            for (index, id) in orderedIds.enumerated() {
                if let position = snapshot.keywordGroups.firstIndex(where: { $0.id == id }) {
                    snapshot.keywordGroups[position].sortOrder = index
                }
            }
            snapshot.keywordGroups.sort { $0.sortOrder < $1.sortOrder }
        }
    }

    // MARK: Helpers

    private func subtreeIds(of id: Int64) -> Set<Int64> {
        guard let tree = snapshot?.keywordTree else { return [] }
        return Set([id] + tree.descendants(of: id))
    }

    /// Photos whose assignments intersect the given keyword ids — the exact set
    /// whose derived facts change on a vocabulary edit.
    private func photoIdsCarrying(keywordIds: Set<Int64>) -> [Int64] {
        guard let snapshot, !keywordIds.isEmpty else { return [] }
        return snapshot.keywordIdsByPhoto.compactMap { photoId, assigned in
            assigned.isDisjoint(with: keywordIds) ? nil : photoId
        }
    }

    private func siblingExists(
        named name: String, parentId: Int64?, excluding: Int64?, tree: KeywordTree
    ) -> Bool {
        let siblings = parentId.map { tree.children(of: $0) } ?? tree.rootIds
        return siblings.contains { $0 != excluding && tree.node($0)?.name == name }
    }

    /// "NEW KEYWORD", "NEW KEYWORD 2", … — the sibling unique constraint must
    /// hold even when the user cancels the rename dialog (spec §8.6 quirk).
    private func uniqueSiblingName(base: String, parentId: Int64?, tree: KeywordTree) -> String {
        guard siblingExists(named: base, parentId: parentId, excluding: nil, tree: tree) else {
            return base
        }
        var suffix = 2
        while siblingExists(named: "\(base) \(suffix)", parentId: parentId, excluding: nil, tree: tree) {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }
}
