import BallastCore
import GRDB

/// Culling mutations, following the CLAUDE.md mutation contract:
/// 1. update the in-memory catalog synchronously (instant UI),
/// 2. persist the delta via async single-row UPDATEs,
/// 3. emit a `CatalogEvent` so derived state updates incrementally.
extension LibraryController {
    /// Sets each photo's rating to `compute(current)`, clamped 0…5 (D5).
    /// Batch semantics (U3): callers pass the whole selection; the whole batch
    /// is one undo step (U8).
    func updateRatings(ids: [Int64], _ compute: (Int) -> Int) {
        let before = captureRatings(of: ids)
        let changed = mutatePhotos(ids: ids) { photo in
            photo.rating = max(0, min(5, compute(photo.rating)))
        }
        guard !changed.isEmpty else { return }
        let changedIds = Set(changed.map(\.id!))
        let undoValues = before.filter { changedIds.contains($0.photoId) }
        registerUndo("Rating Change") { $0.setRatings(undoValues) }
        let updates = changed.map { (photoId: $0.id!, rating: $0.rating) }
        persist { db in try PhotoDAO.setRatings(updates, in: db) }
        emitCatalogEvent(.photosUpdated(updates.map(\.photoId)))
        markNeedsFileWrite(updates.map(\.photoId))
    }

    /// Restores absolute per-photo ratings — the undo/redo path.
    func setRatings(_ values: [(photoId: Int64, rating: Int)]) {
        let before = captureRatings(of: values.map(\.photoId))
        let byId = Dictionary(uniqueKeysWithValues: values.map { ($0.photoId, $0.rating) })
        let changed = mutatePhotos(ids: values.map(\.photoId)) { photo in
            if let rating = photo.id.flatMap({ byId[$0] }) { photo.rating = rating }
        }
        guard !changed.isEmpty else { return }
        let changedIds = Set(changed.map(\.id!))
        registerUndo("Rating Change") {
            $0.setRatings(before.filter { changedIds.contains($0.photoId) })
        }
        let updates = changed.map { (photoId: $0.id!, rating: $0.rating) }
        persist { db in try PhotoDAO.setRatings(updates, in: db) }
        emitCatalogEvent(.photosUpdated(updates.map(\.photoId)))
        markNeedsFileWrite(updates.map(\.photoId))
    }

    /// Advances each photo's stored orientation through the spec §6.6 cycle.
    /// Library-only — orientation is never written to files (U17); display
    /// rotates in the view layer (Q5), so this is instant. One batch = one undo step (U8).
    func rotatePhotos(ids: [Int64]) {
        let before = captureOrientations(of: ids)
        let changed = mutatePhotos(ids: ids) { photo in
            photo.orientation = RotationCycle.next(after: photo.orientation)
        }
        guard !changed.isEmpty else { return }
        let changedIds = Set(changed.map(\.id!))
        let undoValues = before.filter { changedIds.contains($0.photoId) }
        registerUndo("Rotate") { $0.setOrientations(undoValues) }
        let updates = changed.map { (photoId: $0.id!, orientation: $0.orientation) }
        persist { db in try PhotoDAO.setOrientations(updates, in: db) }
        emitCatalogEvent(.photosUpdated(updates.map(\.photoId)))
    }

    /// Restores absolute per-photo orientations — the undo/redo path.
    func setOrientations(_ values: [(photoId: Int64, orientation: Int)]) {
        let before = captureOrientations(of: values.map(\.photoId))
        let byId = Dictionary(uniqueKeysWithValues: values.map { ($0.photoId, $0.orientation) })
        let changed = mutatePhotos(ids: values.map(\.photoId)) { photo in
            if let orientation = photo.id.flatMap({ byId[$0] }) { photo.orientation = orientation }
        }
        guard !changed.isEmpty else { return }
        let changedIds = Set(changed.map(\.id!))
        registerUndo("Rotate") {
            $0.setOrientations(before.filter { changedIds.contains($0.photoId) })
        }
        let updates = changed.map { (photoId: $0.id!, orientation: $0.orientation) }
        persist { db in try PhotoDAO.setOrientations(updates, in: db) }
        emitCatalogEvent(.photosUpdated(updates.map(\.photoId)))
    }

    // MARK: Metadata write-through bookkeeping

    /// Every rating/keyword mutation ends here: flag the photos (memory + DB,
    /// so the write survives a crash) and hand them to the debounced writer.
    /// Undo/redo of such a change goes through the same mutation functions
    /// and therefore marks again — nothing special to do.
    func markNeedsFileWrite(_ ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let newlyDirty = mutatePhotos(ids: ids) { $0.needsFileWrite = true }.map(\.id!)
        if !newlyDirty.isEmpty {
            persist { db in try PhotoDAO.setNeedsFileWrite(true, forPhotoIds: newlyDirty, in: db) }
        }
        fileWriteThrough?.schedule(ids)
    }

    /// The writer confirmed the file carries the current values.
    func clearNeedsFileWrite(_ ids: [Int64]) {
        let cleared = mutatePhotos(ids: ids) { $0.needsFileWrite = false }.map(\.id!)
        guard !cleared.isEmpty else { return }
        persist { db in try PhotoDAO.setNeedsFileWrite(false, forPhotoIds: cleared, in: db) }
    }

    private func captureRatings(of ids: [Int64]) -> [(photoId: Int64, rating: Int)] {
        ids.compactMap { id in photo(withId: id).map { (id, $0.rating) } }
    }

    private func captureOrientations(of ids: [Int64]) -> [(photoId: Int64, orientation: Int)] {
        ids.compactMap { id in photo(withId: id).map { (id, $0.orientation) } }
    }

    /// Async write-through, strictly in submission order via the library's
    /// write pipeline. A failure means memory and DB diverged for the affected
    /// rows — surfaced loudly; the next snapshot load resyncs.
    ///
    /// A nil pipeline is only legitimate while terminating (`drainWrites`
    /// spent it); any other caller has mutated memory with nothing to persist
    /// it — a bug, never silent.
    func persist(_ write: @escaping @Sendable (Database) throws -> Void) {
        guard let writePipeline else {
            guard !isTerminating else { return }
            assertionFailure("persist() without an open write pipeline")
            errorMessage = "Could not save changes to the library.\nNo library is open for writing."
            return
        }
        writePipeline.submit(write)
    }
}
