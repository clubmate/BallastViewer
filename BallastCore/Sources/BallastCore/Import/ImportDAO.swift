import Foundation
import GRDB

public struct ImportItem: Sendable {
    public var path: String
    public var metadata: PhotoFileMetadata

    public init(path: String, metadata: PhotoFileMetadata) {
        self.path = path
        self.metadata = metadata
    }
}

public struct ImportResult: Sendable, Equatable {
    public var added: Int
    public var skipped: Int
    public var batchId: Int64?
}

public enum ImportDAO {
    /// Registers a folder, or updates bookmark/recursive on the existing record —
    /// re-adding a registered folder is the rescan gesture (spec §5.2).
    @discardableResult
    public static func registerFolder(
        path: String,
        bookmark: Data?,
        recursive: Bool,
        in db: Database
    ) throws -> FolderRecord {
        if var existing = try FolderRecord.filter(Column("path") == path).fetchOne(db) {
            existing.bookmark = bookmark ?? existing.bookmark
            existing.recursive = recursive
            try existing.update(db)
            return existing
        }
        var record = FolderRecord(path: path, bookmark: bookmark, recursive: recursive)
        try record.insert(db)
        return record
    }

    /// One import batch per invocation (spec §5.4). Deduplicates by exact path.
    /// When nothing new is found, no batch is created and `lastImportBatchId`
    /// keeps pointing at the previous batch — LAST IMPORT stays useful (Q7).
    ///
    /// Keyword strings are split on `" > "` and stored as node chains; unknown
    /// keywords become ad-hoc nodes (groupId nil), verbatim as in the original.
    /// `existingPaths` lets the caller reuse a path set it already read (the
    /// import flow needs one anyway to skip metadata reads); nil re-reads it
    /// here. The UNIQUE(path) constraint stays the correctness backstop — a
    /// path inserted between the caller's read and this transaction fails the
    /// import loudly instead of importing a duplicate.
    public static func importPhotos(
        _ items: [ImportItem],
        folderId: Int64,
        existingPaths: Set<String>? = nil,
        date: Date = Date(),
        in db: Database
    ) throws -> ImportResult {
        let existingPaths = try existingPaths
            ?? Set(String.fetchAll(db, sql: "SELECT path FROM photo"))
        let newItems = items.filter { !existingPaths.contains($0.path) }
        guard !newItems.isEmpty else {
            return ImportResult(added: 0, skipped: items.count, batchId: nil)
        }

        var batch = ImportBatchRecord(date: date)
        try batch.insert(db)

        // One memo for the whole batch: keyword nodes resolve by dictionary
        // lookup instead of one SELECT per path component per photo.
        let keywordCache = try KeywordPathCache(preloading: db)
        for item in newItems {
            var photo = PhotoRecord(
                folderId: folderId,
                path: item.path,
                rating: item.metadata.rating,
                orientation: item.metadata.orientation,
                captureDate: item.metadata.captureDate,
                dateAdded: date,
                importBatchId: batch.id
            )
            try photo.insert(db)
            for keywordPath in item.metadata.keywords {
                let components = keywordPath.components(separatedBy: KeywordTree.separator)
                    .map(KeywordDAO.normalize).filter { !$0.isEmpty }
                guard !components.isEmpty else { continue }
                let keywordId = try KeywordDAO.ensurePath(
                    components, groupId: nil, cache: keywordCache, in: db
                )
                try PhotoDAO.assignKeyword(keywordId, toPhotoIds: [photo.id!], in: db)
            }
        }

        try LibraryMetaRecord.filter(key: 1)
            .updateAll(db, Column("lastImportBatchId").set(to: batch.id))
        return ImportResult(
            added: newItems.count,
            skipped: items.count - newItems.count,
            batchId: batch.id
        )
    }

    /// For the removal confirmation dialog (U7).
    public static func photoCount(inFolder folderId: Int64, _ db: Database) throws -> Int {
        try PhotoRecord.filter(Column("folderId") == folderId).fetchCount(db)
    }

    /// Removes the folder record and its photos via FK cascade. Membership is by
    /// `folderId`, never by path prefix — `/Photos/Trip2024` is structurally safe
    /// from a removal of `/Photos/Trip` (fixes D4). Files on disk are untouched.
    @discardableResult
    public static func removeFolder(_ folderId: Int64, in db: Database) throws -> Int {
        let count = try photoCount(inFolder: folderId, db)
        try FolderRecord.deleteOne(db, key: folderId)
        return count
    }
}
