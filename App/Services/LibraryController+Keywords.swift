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

    /// U36: assigns the EXACT path, creating it if missing — the dropdown's
    /// "Create" row must bypass the Q16 first-match resolution, or a bare
    /// "2008" could never become a new top-level keyword while a nested
    /// "JAHRE > 2008" exists.
    @discardableResult
    func assignKeyword(exactPath text: String, toPhotoIds photoIds: [Int64]) -> Int64? {
        guard !photoIds.isEmpty, let snapshot else { return nil }
        let components = text
            .components(separatedBy: KeywordTree.separator)
            .map(KeywordDAO.normalize)
            .filter { !$0.isEmpty }
        guard !components.isEmpty else { return nil }
        var keywordId = snapshot.keywordTree.find(pathComponents: components)
        if keywordId == nil {
            guard let result: (leafId: Int64, created: [KeywordRecord]) = writeSync({ db in
                try KeywordDAO.ensurePathCollectingCreated(components, groupId: nil, in: db)
            }) else { return nil }
            mutateSnapshot { $0.keywordTree = $0.keywordTree.inserting(contentsOf: result.created) }
            refreshVocabulary()
            keywordId = result.leafId
        }
        guard let keywordId else { return nil }
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
        invalidateFacts(forPhotoIds: photoIds)
        // U8: the inverse re-registers its own inverse, so redo works too.
        registerUndo("Add Keyword") { $0.removeKeyword(id: keywordId, fromPhotoIds: photoIds) }
        persist { db in try PhotoDAO.assignKeyword(keywordId, toPhotoIds: photoIds, in: db) }
        emitCatalogEvent(.photosUpdated(photoIds))
        markNeedsFileWrite(photoIds)
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
        invalidateFacts(forPhotoIds: photoIds)
        registerUndo("Remove Keyword") { $0.assignKeyword(id: keywordId, toPhotoIds: photoIds) }
        persist { db in try PhotoDAO.removeKeyword(keywordId, fromPhotoIds: photoIds, in: db) }
        emitCatalogEvent(.photosUpdated(photoIds))
        markNeedsFileWrite(photoIds)
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
            guard let result: (leafId: Int64, created: [KeywordRecord]) = writeSync({ db in
                try KeywordDAO.ensurePathCollectingCreated(components, groupId: nil, in: db)
            }) else { return nil }
            // Delta rebuild from memory — no re-fetch of the whole keyword
            // table on the assign-while-culling hot path.
            mutateSnapshot { $0.keywordTree = $0.keywordTree.inserting(contentsOf: result.created) }
            refreshVocabulary()
            return result.leafId
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
        guard let created: KeywordRecord = writeSync({ db in
            var record = KeywordRecord(parentId: parentId, groupId: groupId, name: name)
            try record.insert(db)
            return record
        }) else { return nil }
        mutateSnapshot { $0.keywordTree = $0.keywordTree.inserting(created) }
        refreshVocabulary()
        // No photo carries a brand-new node — no event needed.
        return created.id
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
        let oldPath = snapshot.keywordTree.path(of: id)
        guard writeSync({ db in try KeywordDAO.rename(id, to: name, in: db) }) != nil
        else { return }
        let carriers = photoIdsCarrying(keywordIds: subtreeIds(of: id))
        mutateSnapshot { $0.keywordTree = $0.keywordTree.renaming(id, to: name) }
        refreshVocabulary()
        // Only the carriers' facts changed — wiping the whole cache would make
        // the next rebuild re-derive 50k photos.
        invalidateFacts(forPhotoIds: carriers)
        if let newPath = self.snapshot?.keywordTree.path(of: id), newPath != oldPath {
            keywordPathRenamed?(oldPath, newPath)
        }
        emitCatalogEvent(.photosUpdated(carriers))
        // The file-facing paths of every carrier changed.
        markNeedsFileWrite(carriers)
    }

    /// The same-named SIBLING a rename of `id` to `newName` would collide
    /// with — the editor asks BEFORE renaming so the collision becomes a
    /// merge offer (U40: "_STRASSE" → existing "STRASSE") instead of the
    /// hard error `renameKeyword` raises.
    func keywordRenameMergeCandidate(_ id: Int64, newName: String) -> Int64? {
        guard let tree = snapshot?.keywordTree, let node = tree.node(id) else { return nil }
        let name = KeywordDAO.normalize(newName)
        guard !name.isEmpty, name != node.name else { return nil }
        let siblings = node.parentId.map { tree.children(of: $0) } ?? tree.rootIds
        return siblings.first { $0 != id && tree.node($0)?.name == name }
    }

    /// U40: folds `id` (subtree included) into its sibling `targetId` — the
    /// confirmed rename-collision merge. Assignments union, same-named
    /// children merge recursively; like `moveKeywordToTopLevel`, tree and
    /// join table are reloaded wholesale from the transaction's result.
    /// Not undoable: a merge has no clean inverse.
    func mergeKeyword(_ id: Int64, into targetId: Int64) {
        guard let snapshot, id != targetId,
              snapshot.keywordTree.node(id) != nil,
              snapshot.keywordTree.node(targetId) != nil else { return }
        let oldPath = snapshot.keywordTree.path(of: id)
        // Captured BEFORE the merge while the source ids still exist.
        let carriers = photoIdsCarrying(keywordIds: subtreeIds(of: id))
        struct MergeResult {
            var records: [KeywordRecord]
            var keywordIdsByPhoto: [Int64: Set<Int64>]
        }
        let result: MergeResult? = writeSync { db in
            try KeywordDAO.merge(id, into: targetId, in: db)
            return MergeResult(
                records: try KeywordDAO.fetchAll(db),
                keywordIdsByPhoto: try PhotoDAO.fetchKeywordIdsByPhoto(db)
            )
        }
        guard let result else { return }
        mutateSnapshot {
            $0.keywordTree = KeywordTree(records: result.records)
            $0.keywordIdsByPhoto = result.keywordIdsByPhoto
        }
        refreshVocabulary()
        invalidateFacts(forPhotoIds: carriers)
        // Shortcut/MIDI bindings on the old path re-point at the survivor.
        if let newPath = self.snapshot?.keywordTree.path(of: targetId), newPath != oldPath {
            keywordPathRenamed?(oldPath, newPath)
        }
        emitCatalogEvent(.photosUpdated(carriers))
        // The file-facing paths of every source carrier changed.
        markNeedsFileWrite(carriers)
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
        guard writeSync({ db in try KeywordDAO.deleteSubtree(id, in: db) }) != nil
        else { return }
        mutateSnapshot { snapshot in
            snapshot.keywordTree = snapshot.keywordTree.deletingSubtree(id)
            for photoId in carriers {
                snapshot.keywordIdsByPhoto[photoId]?.subtract(removedIds)
            }
        }
        refreshVocabulary()
        invalidateFacts(forPhotoIds: carriers)
        emitCatalogEvent(.photosUpdated(carriers))
        markNeedsFileWrite(carriers)
    }

    /// Re-homes a top-level keyword into a group (nil = ad-hoc/UNGROUPED).
    /// Effective groups change for the whole subtree, so carriers get an event
    /// (chip colours, group rules, counts).
    func setKeywordGroup(_ id: Int64, groupId: Int64?) {
        guard let snapshot, let node = snapshot.keywordTree.node(id),
              node.groupId != groupId else { return }
        if let groupId, !snapshot.keywordGroups.contains(where: { $0.id == groupId }) { return }
        guard writeSync({ db in try KeywordDAO.setGroup(groupId, forKeywordId: id, in: db) }) != nil
        else { return }
        let carriers = photoIdsCarrying(keywordIds: subtreeIds(of: id))
        mutateSnapshot { $0.keywordTree = $0.keywordTree.settingGroup(groupId, of: id) }
        refreshVocabulary()
        invalidateFacts(forPhotoIds: carriers)
        emitCatalogEvent(.photosUpdated(carriers))
    }

    /// U35: lifts a NESTED keyword (subtree included) to the top level of
    /// `groupId` — the sorting step after a Lightroom import. A same-named
    /// top-level keyword absorbs it (assignments union, children merge), so
    /// the in-memory tree AND join table are reloaded wholesale from the
    /// transaction's result. Not undoable: a merge has no clean inverse.
    func moveKeywordToTopLevel(_ id: Int64, groupId: Int64?) {
        guard let snapshot, snapshot.keywordTree.node(id) != nil else { return }
        if let groupId, !snapshot.keywordGroups.contains(where: { $0.id == groupId }) { return }
        // Every carrier of the subtree gets a new derived path ("JAHRE >
        // 2008" → "2008") — captured BEFORE the move while the ids exist.
        let carriers = photoIdsCarrying(keywordIds: subtreeIds(of: id))
        struct MoveResult {
            var records: [KeywordRecord]
            var keywordIdsByPhoto: [Int64: Set<Int64>]
        }
        let result: MoveResult? = writeSync { db in
            try KeywordDAO.moveToTopLevel(id, groupId: groupId, in: db)
            return MoveResult(
                records: try KeywordDAO.fetchAll(db),
                keywordIdsByPhoto: try PhotoDAO.fetchKeywordIdsByPhoto(db)
            )
        }
        guard let result else { return }
        mutateSnapshot {
            $0.keywordTree = KeywordTree(records: result.records)
            $0.keywordIdsByPhoto = result.keywordIdsByPhoto
        }
        refreshVocabulary()
        invalidateFacts(forPhotoIds: carriers)
        emitCatalogEvent(.photosUpdated(carriers))
        markNeedsFileWrite(carriers)
    }

    // MARK: Groups

    /// Appends a group (end of the Q18 order) and returns it — the editor opens
    /// the group sheet right after, mirroring `createKeyword`.
    @discardableResult
    func createKeywordGroup(name: String, color: String) -> KeywordGroupRecord? {
        guard snapshot != nil,
              let created: KeywordGroupRecord = writeSync({ db in
                  try KeywordDAO.createGroup(name: name, color: color, in: db)
              })
        else { return nil }
        mutateSnapshot { $0.keywordGroups.append(created) }
        refreshVocabulary()
        return created
    }

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
        refreshVocabulary()
    }

    func setKeywordGroupColor(_ id: Int64, color: String) {
        guard let snapshot else { return }
        // The group sheet always saves name AND colour — an unchanged colour
        // must not cost a write plus a carrier-wide event.
        guard snapshot.keywordGroups.first(where: { $0.id == id })?.color != color else { return }
        guard writeSync({ db in try KeywordDAO.setGroupColor(id, color: color, in: db) }) != nil
        else { return }
        // Colors are not query facts, but the grid badges derive dot colors
        // per photo — tell carriers so dots refresh immediately.
        let memberIds = Set(snapshot.keywordTree.allIdsDepthFirst().filter {
            snapshot.keywordTree.effectiveGroupId(of: $0) == id
        })
        let carriers = photoIdsCarrying(keywordIds: memberIds)
        mutateSnapshot { snapshot in
            if let index = snapshot.keywordGroups.firstIndex(where: { $0.id == id }) {
                snapshot.keywordGroups[index].color = color
            }
        }
        refreshVocabulary()
        emitCatalogEvent(.photosUpdated(carriers))
    }

    /// Deletion numbers for the U7 alert: member keywords (they become ad-hoc,
    /// C3) and Smart Collection rules that reference the group (they will stop
    /// matching — the spec §8.3 fix asks for this warning).
    func groupDeletionImpact(_ id: Int64) -> (keywordCount: Int, ruleCount: Int) {
        guard let snapshot else { return (0, 0) }
        // Same predicate as `deleteKeywordGroup`: inherited membership counts,
        // since those keywords lose their effective group too.
        let members = snapshot.keywordTree.allIdsDepthFirst()
            .filter { snapshot.keywordTree.effectiveGroupId(of: $0) == id }
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
        guard writeSync({ db in try KeywordDAO.deleteGroup(id, in: db) }) != nil
        else { return }
        mutateSnapshot { snapshot in
            snapshot.keywordGroups.removeAll { $0.id == id }
            // Mirrors the FK setNull cascade without a re-fetch.
            snapshot.keywordTree = snapshot.keywordTree.removingGroup(id)
        }
        refreshVocabulary()
        invalidateFacts(forPhotoIds: carriers)
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
        refreshVocabulary()
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
