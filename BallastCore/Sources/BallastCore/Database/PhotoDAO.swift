import Foundation
import GRDB

/// Row-level photo operations. All functions run inside a caller-provided
/// transaction (`pool.write { db in … }`) so multi-photo batches stay atomic.
public enum PhotoDAO {
    @discardableResult
    public static func insert(_ photo: PhotoRecord, in db: Database) throws -> PhotoRecord {
        var record = photo
        try record.insert(db)
        return record
    }

    @discardableResult
    public static func insertAll(_ photos: [PhotoRecord], in db: Database) throws -> [PhotoRecord] {
        try photos.map { try insert($0, in: db) }
    }

    public static func fetchAll(_ db: Database) throws -> [PhotoRecord] {
        try PhotoRecord.fetchAll(db)
    }

    public static func setRating(_ rating: Int, forPhotoIds ids: [Int64], in db: Database) throws {
        try PhotoRecord.filter(keys: ids)
            .updateAll(db, Column("rating").set(to: rating))
    }

    public static func setOrientation(_ orientation: Int, forPhotoIds ids: [Int64], in db: Database) throws {
        try PhotoRecord.filter(keys: ids)
            .updateAll(db, Column("orientation").set(to: orientation))
    }

    /// Idempotent: assigning an already-assigned keyword is a no-op.
    public static func assignKeyword(_ keywordId: Int64, toPhotoIds ids: [Int64], in db: Database) throws {
        for photoId in ids {
            try PhotoKeywordRecord(photoId: photoId, keywordId: keywordId)
                .insert(db, onConflict: .ignore)
        }
    }

    public static func removeKeyword(_ keywordId: Int64, fromPhotoIds ids: [Int64], in db: Database) throws {
        try PhotoKeywordRecord
            .filter(Column("keywordId") == keywordId && ids.contains(Column("photoId")))
            .deleteAll(db)
    }

    /// All (photoId, keywordId) pairs — one query, used by the snapshot load.
    public static func fetchKeywordAssignments(_ db: Database) throws -> [(photoId: Int64, keywordId: Int64)] {
        try Row.fetchAll(db, sql: "SELECT photoId, keywordId FROM photoKeyword")
            .map { (photoId: $0["photoId"], keywordId: $0["keywordId"]) }
    }
}
