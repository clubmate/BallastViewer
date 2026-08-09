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
    public var keywordIdsByPhoto: [Int64: Set<Int64>]
    public var keywordTree: KeywordTree
    public var keywordGroups: [KeywordGroupRecord]
    public var smartGroups: [SmartGroupRecord]
    public var collections: [SmartCollectionRecord]
    public var rules: [CollectionRuleRecord]

    public struct MissingMetaError: Error {}

    /// Rule-evaluation facts for one photo (resolved keyword paths + effective
    /// groups). Cheap — proportional to the photo's keyword count.
    public func queryFacts(forPhotoId id: Int64) -> PhotoQueryFacts {
        guard let keywordIds = keywordIdsByPhoto[id], !keywordIds.isEmpty else {
            return PhotoQueryFacts()
        }
        let ids = Array(keywordIds)
        return PhotoQueryFacts(
            keywordPaths: ids.map { keywordTree.path(of: $0) },
            keywordGroupIds: Set(ids.compactMap { keywordTree.effectiveGroupId(of: $0) }),
            foldedKeywordPaths: ids.map { keywordTree.foldedPath(of: $0) }
        )
    }

    public var collectionsById: [Int64: SmartCollectionRecord] {
        Dictionary(uniqueKeysWithValues: collections.compactMap { record in
            record.id.map { ($0, record) }
        })
    }

    public var rulesByCollection: [Int64: [CollectionRuleRecord]] {
        Dictionary(grouping: rules, by: \.collectionId)
    }

    public static func load(_ db: Database) throws -> LibrarySnapshot {
        guard let meta = try LibraryMetaRecord.fetchOne(db) else {
            throw MissingMetaError()
        }
        var keywordIdsByPhoto: [Int64: Set<Int64>] = [:]
        for pair in try PhotoDAO.fetchKeywordAssignments(db) {
            keywordIdsByPhoto[pair.photoId, default: []].insert(pair.keywordId)
        }
        return LibrarySnapshot(
            meta: meta,
            folders: try FolderRecord.order(Column("dateAdded")).fetchAll(db),
            photos: try PhotoRecord.fetchAll(db),
            keywordIdsByPhoto: keywordIdsByPhoto,
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
