import Foundation
import GRDB

/// Everything the app keeps in memory, loaded in one read transaction at library
/// open. This is the hot-path authority; the database is the write-through
/// durable store (see CLAUDE.md mutation contract).
public struct LibrarySnapshot: Sendable {
    public var meta: LibraryMetaRecord
    public var folders: [FolderRecord]
    public var photos: [PhotoRecord]
    /// Keyword ids per photo id — the in-memory form of the join table.
    /// CONFIRMED assignments only; pending AI suggestions live in
    /// `pendingKeywordIdsByPhoto` so nothing confirmed-only (write-through,
    /// facts, counts) ever sees them (U48).
    public var keywordIdsByPhoto: [Int64: Set<Int64>]
    /// Pending AI suggestions per photo id (U48). Rejections are DB-only —
    /// nothing in the hot path needs them.
    public var pendingKeywordIdsByPhoto: [Int64: Set<Int64>] = [:]
    public var keywordTree: KeywordTree
    public var keywordGroups: [KeywordGroupRecord]
    public var smartGroups: [SmartGroupRecord]
    public var collections: [SmartCollectionRecord]
    public var rules: [CollectionRuleRecord]

    public struct MissingMetaError: Error {}

    /// Rule-evaluation facts for one photo (resolved keyword paths + effective
    /// groups + folded filename). Cheap — proportional to the photo's keyword
    /// count; the folded filename costs one ICU fold, paid here once rather
    /// than on every rule evaluation or search pass.
    public func queryFacts(for photo: PhotoRecord) -> PhotoQueryFacts {
        let foldedFilename = CaseInsensitiveMatch.fold(photo.filename)
        guard let id = photo.id, let keywordIds = keywordIdsByPhoto[id], !keywordIds.isEmpty else {
            return PhotoQueryFacts(foldedFilename: foldedFilename)
        }
        let ids = Array(keywordIds)
        return PhotoQueryFacts(
            keywordPaths: ids.map { keywordTree.path(of: $0) },
            keywordGroupIds: Set(ids.compactMap { keywordTree.effectiveGroupId(of: $0) }),
            keywordIds: keywordIds,
            foldedKeywordPaths: ids.map { keywordTree.foldedPath(of: $0) },
            foldedFilename: foldedFilename
        )
    }

    /// Builds a fresh dictionary on every call — cache the result, don't
    /// read it in a loop.
    public func makeCollectionsById() -> [Int64: SmartCollectionRecord] {
        Dictionary(uniqueKeysWithValues: collections.compactMap { record in
            record.id.map { ($0, record) }
        })
    }

    /// Builds a fresh dictionary on every call — cache the result, don't
    /// read it in a loop.
    public func makeRulesByCollection() -> [Int64: [CollectionRuleRecord]] {
        Dictionary(grouping: rules, by: \.collectionId)
    }

    public static func load(_ db: Database) throws -> LibrarySnapshot {
        guard let meta = try LibraryMetaRecord.fetchOne(db) else {
            throw MissingMetaError()
        }
        let keywordIdsByPhoto = try PhotoDAO.fetchKeywordIdsByPhoto(db)
        return LibrarySnapshot(
            meta: meta,
            folders: try FolderRecord.order(Column("dateAdded")).fetchAll(db),
            photos: try PhotoRecord.fetchAll(db),
            keywordIdsByPhoto: keywordIdsByPhoto,
            pendingKeywordIdsByPhoto: try PhotoDAO.fetchPendingKeywordIdsByPhoto(db),
            keywordTree: KeywordTree(records: try KeywordDAO.fetchAll(db)),
            keywordGroups: try KeywordDAO.fetchGroups(db),
            smartGroups: try SmartGroupRecord.order(Column("sortOrder")).fetchAll(db),
            collections: try SmartCollectionRecord
                .order(Column("groupId"), Column("sortOrder")).fetchAll(db),
            rules: try CollectionRuleRecord
                .order(Column("collectionId"), Column("sortOrder")).fetchAll(db)
        )
    }
}
