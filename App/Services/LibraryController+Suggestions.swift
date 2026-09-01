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
        registerUndo("Reject Suggestion") { $0.restorePendingKeyword(id: keywordId, forPhotoIds: photoIds) }
        persist { db in
            try PhotoDAO.deletePendingKeyword(keywordId, forPhotoIds: photoIds, in: db)
            try PhotoDAO.insertRejected(keywordId, forPhotoIds: photoIds, in: db)
        }
        emitCatalogEvent(.photosUpdated(photoIds))
    }

    /// Undo of a reject: the suggestion comes back, the tombstones go away.
    func restorePendingKeyword(id keywordId: Int64, forPhotoIds photoIds: [Int64]) {
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
            try PhotoDAO.assignPendingKeywords(
                photoIds.map { PhotoKeywordPair(photoId: $0, keywordId: keywordId) }, in: db
            )
        }
        emitCatalogEvent(.photosUpdated(photoIds))
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
        registerUndo("Discard Suggestions") { $0.restoreDiscardedSuggestions(restore) }
        persist { db in try PhotoDAO.deletePendingPairs(restore, in: db) }
        emitCatalogEvent(.photosUpdated(Array(changed)))
    }

    /// Undo of a discard: the suggestions come back as pending (skipping any
    /// pair that became confirmed or pending again in the meantime).
    func restoreDiscardedSuggestions(_ pairs: [PhotoKeywordPair]) {
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
}
