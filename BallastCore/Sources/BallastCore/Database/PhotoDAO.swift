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

    /// Stamps the photos a Lightroom import covered (U43) — later imports
    /// leave stamped photos alone. Same single-row UPDATE shape as above.
    public static func setLightroomMerged(_ date: Date, forPhotoIds ids: [Int64], in db: Database) throws {
        let statement = try db.cachedStatement(sql: "UPDATE photo SET lightroomMergedAt = ? WHERE id = ?")
        for id in ids {
            try statement.execute(arguments: [date, id])
        }
    }

    /// Photos an earlier Lightroom import already covered.
    public static func lightroomMergedPhotoIds(_ db: Database) throws -> Set<Int64> {
        Set(try Int64.fetchAll(db, sql: "SELECT id FROM photo WHERE lightroomMergedAt IS NOT NULL"))
    }

    /// Idempotent: assigning an already-assigned keyword is a no-op. A row
    /// sitting at `pending` (AI suggestion, U48) is promoted to `confirmed` —
    /// manually assigning a suggested keyword is an implicit accept.
    public static func assignKeyword(_ keywordId: Int64, toPhotoIds ids: [Int64], in db: Database) throws {
        let statement = try db.cachedStatement(
            sql: """
                INSERT INTO photoKeyword (photoId, keywordId, status) VALUES (?, ?, 'confirmed')
                ON CONFLICT(photoId, keywordId) DO UPDATE SET status = 'confirmed'
                    WHERE status = 'pending'
                """
        )
        for photoId in ids {
            try statement.execute(arguments: [photoId, keywordId])
        }
    }

    public static func removeKeyword(_ keywordId: Int64, fromPhotoIds ids: [Int64], in db: Database) throws {
        for chunk in idChunks(ids) {
            try PhotoKeywordRecord
                .filter(Column("keywordId") == keywordId && chunk.contains(Column("photoId")))
                .deleteAll(db)
        }
    }

    /// Replaces a photo's entire CONFIRMED assignment set — metadata Load,
    /// where the file's keyword list wins wholesale (spec §6.4). Pending AI
    /// suggestions and rejection memory survive the Load (they are user-review
    /// state, not file state); a pending keyword that IS in the file gets
    /// promoted to confirmed by the upsert.
    public static func setKeywords(_ keywordIds: [Int64], forPhotoId photoId: Int64, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM photoKeyword WHERE photoId = ? AND status = 'confirmed'",
            arguments: [photoId]
        )
        let statement = try db.cachedStatement(
            sql: """
                INSERT INTO photoKeyword (photoId, keywordId, status) VALUES (?, ?, 'confirmed')
                ON CONFLICT(photoId, keywordId) DO UPDATE SET status = 'confirmed'
                    WHERE status = 'pending'
                """
        )
        for keywordId in keywordIds {
            try statement.execute(arguments: [photoId, keywordId])
        }
    }

    // MARK: AI suggestions (U48)

    /// Pending suggestions as keyword-id sets per photo id — the snapshot's
    /// second map, same shape as `fetchKeywordIdsByPhoto`.
    public static func fetchPendingKeywordIdsByPhoto(_ db: Database) throws -> [Int64: Set<Int64>] {
        var result: [Int64: Set<Int64>] = [:]
        let cursor = try Row.fetchCursor(
            db, sql: "SELECT photoId, keywordId FROM photoKeyword WHERE status = 'pending'")
        while let row = try cursor.next() {
            let photoId: Int64 = row[0]
            let keywordId: Int64 = row[1]
            result[photoId, default: []].insert(keywordId)
        }
        return result
    }

    /// Inserts suggestion pairs as pending. OR IGNORE on purpose: an existing
    /// CONFIRMED row must never be demoted by a suggestion run.
    public static func assignPendingKeywords(_ pairs: [PhotoKeywordPair], in db: Database) throws {
        let statement = try db.cachedStatement(
            sql: "INSERT OR IGNORE INTO photoKeyword (photoId, keywordId, status) VALUES (?, ?, 'pending')"
        )
        for pair in pairs {
            try statement.execute(arguments: [pair.photoId, pair.keywordId])
        }
    }

    /// Accept: pending → confirmed (only rows actually pending).
    public static func confirmPendingKeyword(_ keywordId: Int64, forPhotoIds ids: [Int64], in db: Database) throws {
        let statement = try db.cachedStatement(
            sql: "UPDATE photoKeyword SET status = 'confirmed' WHERE photoId = ? AND keywordId = ? AND status = 'pending'"
        )
        for id in ids {
            try statement.execute(arguments: [id, keywordId])
        }
    }

    /// Undo of an accept: confirmed → pending.
    public static func demoteKeywordToPending(_ keywordId: Int64, forPhotoIds ids: [Int64], in db: Database) throws {
        let statement = try db.cachedStatement(
            sql: "UPDATE photoKeyword SET status = 'pending' WHERE photoId = ? AND keywordId = ? AND status = 'confirmed'"
        )
        for id in ids {
            try statement.execute(arguments: [id, keywordId])
        }
    }

    /// Reject (or restore-undo): drops the pending rows outright. Confirmed
    /// rows are untouched.
    public static func deletePendingKeyword(_ keywordId: Int64, forPhotoIds ids: [Int64], in db: Database) throws {
        let statement = try db.cachedStatement(
            sql: "DELETE FROM photoKeyword WHERE photoId = ? AND keywordId = ? AND status = 'pending'"
        )
        for id in ids {
            try statement.execute(arguments: [id, keywordId])
        }
    }

    /// Discard (U48 emergency exit): drops the given PENDING pairs without
    /// leaving rejection memory — a later run may suggest them again.
    /// Confirmed rows are untouched.
    public static func deletePendingPairs(_ pairs: [PhotoKeywordPair], in db: Database) throws {
        let statement = try db.cachedStatement(
            sql: "DELETE FROM photoKeyword WHERE photoId = ? AND keywordId = ? AND status = 'pending'"
        )
        for pair in pairs {
            try statement.execute(arguments: [pair.photoId, pair.keywordId])
        }
    }

    // MARK: Rejection memory (U48)

    public static func fetchRejectedPairs(_ db: Database) throws -> Set<PhotoKeywordPair> {
        var result = Set<PhotoKeywordPair>()
        let cursor = try Row.fetchCursor(db, sql: "SELECT photoId, keywordId FROM rejectedSuggestion")
        while let row = try cursor.next() {
            result.insert(PhotoKeywordPair(photoId: row[0], keywordId: row[1]))
        }
        return result
    }

    public static func insertRejected(_ keywordId: Int64, forPhotoIds ids: [Int64], in db: Database) throws {
        let statement = try db.cachedStatement(
            sql: "INSERT OR IGNORE INTO rejectedSuggestion (photoId, keywordId) VALUES (?, ?)"
        )
        for id in ids {
            try statement.execute(arguments: [id, keywordId])
        }
    }

    /// Undo of a reject: the tombstones go away again.
    public static func deleteRejected(_ keywordId: Int64, forPhotoIds ids: [Int64], in db: Database) throws {
        let statement = try db.cachedStatement(
            sql: "DELETE FROM rejectedSuggestion WHERE photoId = ? AND keywordId = ?"
        )
        for id in ids {
            try statement.execute(arguments: [id, keywordId])
        }
    }

    /// The join table as keyword-id sets per photo id — the snapshot's
    /// in-memory form, built straight off a row cursor with positional
    /// column access (no intermediate row array or tuple list).
    ///
    /// CONFIRMED rows only — this single filter is what keeps pending AI
    /// suggestions (U48) out of the XMP write-through, search facts, chips,
    /// and counts, which all derive from the snapshot map built here.
    public static func fetchKeywordIdsByPhoto(_ db: Database) throws -> [Int64: Set<Int64>] {
        var result: [Int64: Set<Int64>] = [:]
        let photoCount = try Int.fetchOne(
            db, sql: "SELECT COUNT(DISTINCT photoId) FROM photoKeyword WHERE status = 'confirmed'") ?? 0
        result.reserveCapacity(photoCount)
        let cursor = try Row.fetchCursor(
            db, sql: "SELECT photoId, keywordId FROM photoKeyword WHERE status = 'confirmed'")
        while let row = try cursor.next() {
            let photoId: Int64 = row[0]
            let keywordId: Int64 = row[1]
            result[photoId, default: []].insert(keywordId)
        }
        return result
    }
}
