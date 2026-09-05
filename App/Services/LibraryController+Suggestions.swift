import BallastCore
import Foundation
import GRDB

/// U48 Stage 2: the pending-suggestion lifecycle. All mutations follow the
/// contract order of `assignKeyword` (memory → facts → undo → persist →
/// event → maybe needsFileWrite) — with one deliberate asymmetry: pending
/// state is NEVER file-facing and NEVER a query fact, so only accept/demote
/// (which change the confirmed set) invalidate facts or touch the
/// write-through.
extension LibraryController {
    /// The suggestion run delivers its matches here, in batches. No undo (a
    /// run is re-runnable, like a Lightroom merge), no facts, no file write.
    /// `libraryUUID` is the library the run was started on: photo and keyword
    /// ids are per-library autoincrements, so a batch arriving after a library
    /// switch would land on unrelated rows — it is dropped instead.
    func applySuggestions(_ pairs: [PhotoKeywordPair], libraryUUID: String) {
        guard let snapshot, snapshot.meta.libraryUUID == libraryUUID else { return }
        var fresh: [PhotoKeywordPair] = []
        var changed = Set<Int64>()
        mutateSnapshot { snapshot in
            for pair in pairs {
                guard snapshot.keywordTree.node(pair.keywordId) != nil,
                      !(snapshot.keywordIdsByPhoto[pair.photoId]?.contains(pair.keywordId) ?? false),
                      !(snapshot.pendingKeywordIdsByPhoto[pair.photoId]?.contains(pair.keywordId) ?? false)
                else { continue }
                snapshot.pendingKeywordIdsByPhoto[pair.photoId, default: []].insert(pair.keywordId)
                fresh.append(pair)
                changed.insert(pair.photoId)
            }
        }
        guard !fresh.isEmpty else { return }
        let inserts = fresh
        persist { db in try PhotoDAO.assignPendingKeywords(inserts, in: db) }
        emitCatalogEvent(.photosUpdated(Array(changed)))
    }

    /// ✓ on a pending chip: the suggestion becomes a normal keyword — from
    /// here on the standard machinery applies, including the file write.
    func acceptPendingKeyword(id keywordId: Int64, forPhotoIds photoIds: [Int64]) {
        var changed: [Int64] = []
        mutateSnapshot { snapshot in
            for photoId in photoIds
            where snapshot.pendingKeywordIdsByPhoto[photoId]?.contains(keywordId) == true {
                snapshot.pendingKeywordIdsByPhoto[photoId]?.remove(keywordId)
                snapshot.keywordIdsByPhoto[photoId, default: []].insert(keywordId)
                changed.append(photoId)
            }
        }
        guard !changed.isEmpty else { return }
        let photoIds = changed
        invalidateFacts(forPhotoIds: photoIds)
        registerUndo("Accept Suggestion") { $0.demotePendingKeyword(id: keywordId, forPhotoIds: photoIds) }
        persist { db in try PhotoDAO.confirmPendingKeyword(keywordId, forPhotoIds: photoIds, in: db) }
        emitCatalogEvent(.photosUpdated(photoIds))
        markNeedsFileWrite(photoIds)
    }

    /// Undo of an accept: confirmed → pending again. Marks needsFileWrite on
    /// purpose — the accept's XMP write may already have run, so the file can
    /// carry a keyword the catalog no longer confirms.
    func demotePendingKeyword(id keywordId: Int64, forPhotoIds photoIds: [Int64]) {
        var changed: [Int64] = []
        mutateSnapshot { snapshot in
            for photoId in photoIds
            where snapshot.keywordIdsByPhoto[photoId]?.contains(keywordId) == true {
                snapshot.keywordIdsByPhoto[photoId]?.remove(keywordId)
                snapshot.pendingKeywordIdsByPhoto[photoId, default: []].insert(keywordId)
                changed.append(photoId)
            }
        }
        guard !changed.isEmpty else { return }
        let photoIds = changed
        invalidateFacts(forPhotoIds: photoIds)
        registerUndo("Accept Suggestion") { $0.acceptPendingKeyword(id: keywordId, forPhotoIds: photoIds) }
        persist { db in try PhotoDAO.demoteKeywordToPending(keywordId, forPhotoIds: photoIds, in: db) }
        emitCatalogEvent(.photosUpdated(photoIds))
        markNeedsFileWrite(photoIds)
    }

    /// ✗ on a pending chip: the suggestion disappears AND is remembered — a
    /// later run never re-suggests the pair. Nothing file-facing changed.
    /// A keyword the model coined (U50) is remembered by PATH as well, and
    /// collected when this was the last thing holding it.
    func rejectPendingKeyword(id keywordId: Int64, forPhotoIds photoIds: [Int64]) {
        var changed: [Int64] = []
        mutateSnapshot { snapshot in
            for photoId in photoIds
            where snapshot.pendingKeywordIdsByPhoto[photoId]?.contains(keywordId) == true {
                snapshot.pendingKeywordIdsByPhoto[photoId]?.remove(keywordId)
                changed.append(photoId)
            }
        }
        guard !changed.isEmpty else { return }
        let photoIds = changed
        let coinedPath = snapshot?.keywordTree.node(keywordId)?.aiCreated == true
            ? snapshot?.keywordTree.path(of: keywordId) : nil
        persist { db in
            try PhotoDAO.deletePendingKeyword(keywordId, forPhotoIds: photoIds, in: db)
            try PhotoDAO.insertRejected(keywordId, forPhotoIds: photoIds, in: db)
            if let coinedPath {
                try PhotoDAO.insertRejectedAIAnswer(path: coinedPath, forPhotoIds: photoIds, in: db)
            }
        }
        emitCatalogEvent(.photosUpdated(photoIds))
        let collected = collectOrphanedAIKeywords([keywordId])
        registerUndo("Reject Suggestion") {
            $0.restorePendingKeyword(id: keywordId, forPhotoIds: photoIds, coinedPath: coinedPath, collected: collected)
        }
    }

    /// Undo of a reject: the suggestion comes back, the tombstones go away
    /// (and a collected coined keyword is re-created under its old id first).
    func restorePendingKeyword(
        id keywordId: Int64, forPhotoIds photoIds: [Int64], coinedPath: String? = nil, collected: [KeywordRecord] = []
    ) {
        restoreCollectedAIKeywords(collected)
        var changed: [Int64] = []
        mutateSnapshot { snapshot in
            for photoId in photoIds
            where !(snapshot.keywordIdsByPhoto[photoId]?.contains(keywordId) ?? false)
                && !(snapshot.pendingKeywordIdsByPhoto[photoId]?.contains(keywordId) ?? false) {
                snapshot.pendingKeywordIdsByPhoto[photoId, default: []].insert(keywordId)
                changed.append(photoId)
            }
        }
        guard !changed.isEmpty else { return }
        let photoIds = changed
        registerUndo("Reject Suggestion") { $0.rejectPendingKeyword(id: keywordId, forPhotoIds: photoIds) }
        persist { db in
            try PhotoDAO.deleteRejected(keywordId, forPhotoIds: photoIds, in: db)
            if let coinedPath {
                try PhotoDAO.deleteRejectedAIAnswer(path: coinedPath, forPhotoIds: photoIds, in: db)
            }
            try PhotoDAO.assignPendingKeywords(
                photoIds.map { PhotoKeywordPair(photoId: $0, keywordId: keywordId) }, in: db
            )
        }
        emitCatalogEvent(.photosUpdated(photoIds))
    }

    /// AI ▸ Accept / Reject All Suggestions on Selection: every pending chip
    /// of the given photos at once (one undo step each — they land in the
    /// same event group).
    func acceptAllPendingKeywords(forPhotoIds photoIds: [Int64]) {
        for (keywordId, photos) in pendingByKeyword(forPhotoIds: photoIds) {
            acceptPendingKeyword(id: keywordId, forPhotoIds: photos)
        }
    }

    func rejectAllPendingKeywords(forPhotoIds photoIds: [Int64]) {
        for (keywordId, photos) in pendingByKeyword(forPhotoIds: photoIds) {
            rejectPendingKeyword(id: keywordId, forPhotoIds: photos)
        }
    }

    /// Whether any of the photos carries a pending suggestion.
    func hasPendingKeywords(forPhotoIds photoIds: [Int64]) -> Bool {
        guard let snapshot else { return false }
        return photoIds.contains { !(snapshot.pendingKeywordIdsByPhoto[$0]?.isEmpty ?? true) }
    }

    private func pendingByKeyword(forPhotoIds photoIds: [Int64]) -> [Int64: [Int64]] {
        guard let snapshot else { return [:] }
        var result: [Int64: [Int64]] = [:]
        for photoId in photoIds {
            for keywordId in snapshot.pendingKeywordIdsByPhoto[photoId] ?? [] {
                result[keywordId, default: []].append(photoId)
            }
        }
        return result
    }

    // MARK: Coined keywords (U50)

    /// Finds or coins the keyword for an open answer — a sync write because
    /// the id is needed for the suggestion pair right away. Nil when the
    /// parent keyword vanished mid-run.
    func ensureCoinedKeyword(_ coined: AICoinedKeyword) -> Int64? {
        guard let snapshot else { return nil }
        if let parentId = coined.parentKeywordId, snapshot.keywordTree.node(parentId) == nil { return nil }
        guard let result: (id: Int64, created: KeywordRecord?) = writeSync({ db in
            try KeywordDAO.ensureChild(named: coined.name, parentId: coined.parentKeywordId, aiCreated: true, in: db)
        }) else { return nil }
        if let created = result.created {
            mutateSnapshot { $0.keywordTree = $0.keywordTree.inserting(created) }
            refreshVocabulary()
        }
        return result.id
    }

    /// The path a coined keyword WOULD have — the key of its rejection memory.
    func coinedKeywordPath(_ coined: AICoinedKeyword) -> String? {
        guard let tree = snapshot?.keywordTree else { return nil }
        guard let parentId = coined.parentKeywordId else { return coined.name }
        guard tree.node(parentId) != nil else { return nil }
        return tree.path(of: parentId) + " > " + coined.name
    }

    /// Rejection memory of coined keywords, by path — read once per run.
    func fetchRejectedAIAnswerPaths() -> [Int64: Set<String>] {
        writeSync { db in try PhotoDAO.fetchRejectedAIAnswerPaths(db) } ?? [:]
    }

    /// Deletes those of `keywordIds` the model coined and nothing holds any
    /// more — no assignment (confirmed or pending), no child, no
    /// questionnaire pointing at them. Decided in memory (the maps are the
    /// authority), persisted in order behind the pending delete that freed
    /// them. Returns the removed rows for undo.
    @discardableResult
    func collectOrphanedAIKeywords(_ keywordIds: Set<Int64>) -> [KeywordRecord] {
        guard let snapshot else { return [] }
        var referenced = Set<Int64>()
        for profile in snapshot.aiProfiles {
            referenced.formUnion(profile.keywordIds)
            referenced.formUnion(profile.allQuestions.compactMap(\.parentKeywordId))
        }
        var orphans: [KeywordRecord] = []
        for id in keywordIds.subtracting(referenced) {
            guard let node = snapshot.keywordTree.node(id), node.aiCreated,
                  snapshot.keywordTree.children(of: id).isEmpty,
                  !snapshot.keywordIdsByPhoto.values.contains(where: { $0.contains(id) }),
                  !snapshot.pendingKeywordIdsByPhoto.values.contains(where: { $0.contains(id) })
            else { continue }
            orphans.append(node)
        }
        guard !orphans.isEmpty else { return [] }
        mutateSnapshot { snapshot in
            for orphan in orphans {
                if let id = orphan.id { snapshot.keywordTree = snapshot.keywordTree.deletingSubtree(id) }
            }
        }
        refreshVocabulary()
        let ids = orphans.compactMap(\.id)
        persist { db in
            for id in ids { try KeywordDAO.deleteSubtree(id, in: db) }
        }
        return orphans
    }

    /// Undo counterpart of `collectOrphanedAIKeywords`: the rows come back
    /// under their old ids (skipping any that exist again).
    func restoreCollectedAIKeywords(_ records: [KeywordRecord]) {
        guard !records.isEmpty, let snapshot else { return }
        let missing = records.filter { $0.id.map { snapshot.keywordTree.node($0) == nil } ?? false }
        guard !missing.isEmpty else { return }
        mutateSnapshot { $0.keywordTree = $0.keywordTree.inserting(contentsOf: missing) }
        refreshVocabulary()
        persist { db in try KeywordDAO.restore(missing, in: db) }
    }

    // MARK: Discard (emergency exit)

    /// Every pending suggestion in the library, as pairs — what "Discard All
    /// Suggestions" removes.
    var allPendingSuggestionPairs: [PhotoKeywordPair] {
        (snapshot?.pendingKeywordIdsByPhoto ?? [:]).flatMap { photoId, keywordIds in
            keywordIds.map { PhotoKeywordPair(photoId: photoId, keywordId: $0) }
        }
    }

    /// The emergency exit after a bad run (user request 2026-09-02): the
    /// pending suggestions vanish as if the run had never happened — NO
    /// rejection memory, so a later run may offer them again. Undoable.
    /// Nothing file-facing changes (pending never was).
    func discardPendingSuggestions(_ pairs: [PhotoKeywordPair]) {
        var dropped: [PhotoKeywordPair] = []
        var changed = Set<Int64>()
        mutateSnapshot { snapshot in
            for pair in pairs
            where snapshot.pendingKeywordIdsByPhoto[pair.photoId]?.contains(pair.keywordId) == true {
                snapshot.pendingKeywordIdsByPhoto[pair.photoId]?.remove(pair.keywordId)
                dropped.append(pair)
                changed.insert(pair.photoId)
            }
        }
        guard !dropped.isEmpty else { return }
        let restore = dropped
        persist { db in try PhotoDAO.deletePendingPairs(restore, in: db) }
        emitCatalogEvent(.photosUpdated(Array(changed)))
        let collected = collectOrphanedAIKeywords(Set(restore.map(\.keywordId)))
        registerUndo("Discard Suggestions") { $0.restoreDiscardedSuggestions(restore, collected: collected) }
    }

    /// Undo of a discard: the suggestions come back as pending (skipping any
    /// pair that became confirmed or pending again in the meantime).
    func restoreDiscardedSuggestions(_ pairs: [PhotoKeywordPair], collected: [KeywordRecord] = []) {
        restoreCollectedAIKeywords(collected)
        var fresh: [PhotoKeywordPair] = []
        var changed = Set<Int64>()
        mutateSnapshot { snapshot in
            for pair in pairs {
                guard snapshot.keywordTree.node(pair.keywordId) != nil,
                      !(snapshot.keywordIdsByPhoto[pair.photoId]?.contains(pair.keywordId) ?? false),
                      !(snapshot.pendingKeywordIdsByPhoto[pair.photoId]?.contains(pair.keywordId) ?? false)
                else { continue }
                snapshot.pendingKeywordIdsByPhoto[pair.photoId, default: []].insert(pair.keywordId)
                fresh.append(pair)
                changed.insert(pair.photoId)
            }
        }
        guard !fresh.isEmpty else { return }
        let inserts = fresh
        registerUndo("Discard Suggestions") { $0.discardPendingSuggestions(inserts) }
        persist { db in try PhotoDAO.assignPendingKeywords(inserts, in: db) }
        emitCatalogEvent(.photosUpdated(Array(changed)))
    }

    /// One synchronous read per suggestion run — the skip set for the engine.
    func fetchRejectedSuggestionPairs() -> Set<PhotoKeywordPair> {
        writeSync { db in try PhotoDAO.fetchRejectedPairs(db) } ?? []
    }

    // MARK: Profiles (U49)

    /// Saves a profile whole (insert or replace) — not undoable, not file-
    /// facing, not a query fact: only the snapshot's profile list changes.
    /// Returns the saved profile with ids assigned.
    @discardableResult
    func saveAIProfile(_ profile: AIProfile) -> AIProfile? {
        guard snapshot != nil else { return nil }
        guard let saved = writeSync({ db in try AIProfileDAO.save(profile, in: db) }) else { return nil }
        mutateSnapshot { snapshot in
            if let index = snapshot.aiProfiles.firstIndex(where: { $0.id == saved.id }) {
                snapshot.aiProfiles[index] = saved
            } else {
                snapshot.aiProfiles.append(saved)
            }
        }
        return saved
    }

    func deleteAIProfile(_ id: Int64) {
        guard snapshot?.aiProfiles.contains(where: { $0.id == id }) == true else { return }
        guard writeSync({ db in try AIProfileDAO.delete(id, in: db) }) != nil else { return }
        mutateSnapshot { $0.aiProfiles.removeAll { $0.id == id } }
    }

    func setAIProfileEnabled(_ id: Int64, _ enabled: Bool) {
        guard let index = snapshot?.aiProfiles.firstIndex(where: { $0.id == id }) else { return }
        guard writeSync({ db in try AIProfileDAO.setEnabled(enabled, profileId: id, in: db) }) != nil else { return }
        mutateSnapshot { $0.aiProfiles[index].enabled = enabled }
    }
}
