import BallastCore
import GRDB

/// Culling mutations, following the CLAUDE.md mutation contract:
/// 1. update the in-memory catalog synchronously (instant UI),
/// 2. persist the delta via async single-row UPDATEs,
/// 3. emit a `CatalogEvent` so derived state updates incrementally.
extension LibraryController {
    /// Sets each photo's rating to `compute(current)`, clamped 0…5 (D5).
    /// Batch semantics (U3): callers pass the whole selection.
    func updateRatings(ids: [Int64], _ compute: (Int) -> Int) {
        let changed = mutatePhotos(ids: ids) { photo in
            photo.rating = max(0, min(5, compute(photo.rating)))
        }
        guard !changed.isEmpty else { return }
        let updates = changed.map { (photoId: $0.id!, rating: $0.rating) }
        persist { db in try PhotoDAO.setRatings(updates, in: db) }
        emitCatalogEvent(.photosUpdated(updates.map(\.photoId)))
    }

    /// Advances each photo's stored orientation through the spec §6.6 cycle.
    /// Library-only until metadata write-back (step 10); display rotates in the
    /// view layer (Q5), so this is instant.
    func rotatePhotos(ids: [Int64]) {
        let changed = mutatePhotos(ids: ids) { photo in
            photo.orientation = RotationCycle.next(after: photo.orientation)
        }
        guard !changed.isEmpty else { return }
        let updates = changed.map { (photoId: $0.id!, orientation: $0.orientation) }
        persist { db in try PhotoDAO.setOrientations(updates, in: db) }
        emitCatalogEvent(.photosUpdated(updates.map(\.photoId)))
    }

    /// Async write-through. A failure here means memory and DB diverged for the
    /// affected rows — surfaced loudly; the next snapshot load resyncs.
    func persist(_ write: @escaping @Sendable (Database) throws -> Void) {
        guard let library else { return }
        Task {
            do {
                try await library.pool.write(write)
            } catch {
                errorMessage = "Could not save changes to the library.\n\(error.localizedDescription)"
            }
        }
    }
}
