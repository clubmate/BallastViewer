import Foundation
import GRDB

/// Row-level photo operations. All functions run inside a caller-provided
/// transaction (`pool.write { db in … }`) so multi-photo batches stay atomic.
public enum PhotoDAO {
    public static func fetchAll(_ db: Database) throws -> [PhotoRecord] {
        try PhotoRecord.fetchAll(db)
    }

    /// SQLite binds one variable per id; a "Select All" over a big library can
    /// exceed SQLITE_MAX_VARIABLE_NUMBER, so every id list is chunked.
    static let idChunkSize = 500

    /// `ids` split into `idChunkSize`-sized slices, in order.
    private static func idChunks(_ ids: [Int64]) -> [ArraySlice<Int64>] {
        stride(from: 0, to: ids.count, by: idChunkSize)
            .map { ids[$0..<min($0 + idChunkSize, ids.count)] }
    }

    public static func setRating(_ rating: Int, forPhotoIds ids: [Int64], in db: Database) throws {
        for chunk in idChunks(ids) {
            try PhotoRecord.filter(keys: chunk)
                .updateAll(db, Column("rating").set(to: rating))
        }
    }

    public static func setOrientation(_ orientation: Int, forPhotoIds ids: [Int64], in db: Database) throws {
        for chunk in idChunks(ids) {
            try PhotoRecord.filter(keys: chunk)
                .updateAll(db, Column("orientation").set(to: orientation))
        }
    }

    /// Per-photo values (ratingUp/ratingDown produce different results across a
    /// batch). Single-row UPDATEs via one cached statement, caller's transaction.
    public static func setRatings(_ updates: [(photoId: Int64, rating: Int)], in db: Database) throws {
        let statement = try db.cachedStatement(sql: "UPDATE photo SET rating = ? WHERE id = ?")
        for update in updates {
            try statement.execute(arguments: [update.rating, update.photoId])
        }
    }

    /// Per-photo values (each photo advances its own orientation cycle).
    public static func setOrientations(_ updates: [(photoId: Int64, orientation: Int)], in db: Database) throws {
        let statement = try db.cachedStatement(sql: "UPDATE photo SET orientation = ? WHERE id = ?")
        for update in updates {
            try statement.execute(arguments: [update.orientation, update.photoId])
        }
    }

    /// Metadata write-through dirty flag (single-row UPDATEs, one cached
    /// statement, caller's transaction — same shape as the rating writes).
    public static func setNeedsFileWrite(_ flag: Bool, forPhotoIds ids: [Int64], in db: Database) throws {
        let statement = try db.cachedStatement(sql: "UPDATE photo SET needsFileWrite = ? WHERE id = ?")
        for id in ids {
            try statement.execute(arguments: [flag, id])
        }
    }

    /// Photos whose files still lag behind the library — re-queued on open.
    public static func photoIdsNeedingFileWrite(_ db: Database) throws -> [Int64] {
        try Int64.fetchAll(db, sql: "SELECT id FROM photo WHERE needsFileWrite = 1 ORDER BY id")
    }

    /// Idempotent: assigning an already-assigned keyword is a no-op.
    public static func assignKeyword(_ keywordId: Int64, toPhotoIds ids: [Int64], in db: Database) throws {
        for photoId in ids {
            try PhotoKeywordRecord(photoId: photoId, keywordId: keywordId)
                .insert(db, onConflict: .ignore)
        }
    }

    public static func removeKeyword(_ keywordId: Int64, fromPhotoIds ids: [Int64], in db: Database) throws {
        for chunk in idChunks(ids) {
            try PhotoKeywordRecord
                .filter(Column("keywordId") == keywordId && chunk.contains(Column("photoId")))
                .deleteAll(db)
        }
    }

    /// Replaces a photo's entire assignment set — metadata Load, where the
    /// file's keyword list wins wholesale (spec §6.4).
    public static func setKeywords(_ keywordIds: [Int64], forPhotoId photoId: Int64, in db: Database) throws {
        try PhotoKeywordRecord.filter(Column("photoId") == photoId).deleteAll(db)
        for keywordId in keywordIds {
            try PhotoKeywordRecord(photoId: photoId, keywordId: keywordId)
                .insert(db, onConflict: .ignore)
        }
    }

    /// The join table as keyword-id sets per photo id — the snapshot's
    /// in-memory form, built straight off a row cursor with positional
    /// column access (no intermediate row array or tuple list).
    public static func fetchKeywordIdsByPhoto(_ db: Database) throws -> [Int64: Set<Int64>] {
        var result: [Int64: Set<Int64>] = [:]
        let photoCount = try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT photoId) FROM photoKeyword") ?? 0
        result.reserveCapacity(photoCount)
        let cursor = try Row.fetchCursor(db, sql: "SELECT photoId, keywordId FROM photoKeyword")
        while let row = try cursor.next() {
            let photoId: Int64 = row[0]
            let keywordId: Int64 = row[1]
            result[photoId, default: []].insert(keywordId)
        }
        return result
    }
}
