import Foundation
import GRDB

public enum CollectionDAO {
    // MARK: Groups

    @discardableResult
    public static func createGroup(name: String, in db: Database) throws -> SmartGroupRecord {
        let maxOrder = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM smartGroup") ?? -1
        var record = SmartGroupRecord(name: name, sortOrder: maxOrder + 1)
        try record.insert(db)
        return record
    }

    public static func renameGroup(_ id: Int64, to name: String, in db: Database) throws {
        try SmartGroupRecord.filter(key: id).updateAll(db, Column("name").set(to: name))
    }

    /// Deletes the group, its collections and their rules (FK cascade).
    public static func deleteGroup(_ id: Int64, in db: Database) throws {
        try SmartGroupRecord.deleteOne(db, key: id)
    }

    public static func reorderGroups(_ orderedIds: [Int64], in db: Database) throws {
        for (index, id) in orderedIds.enumerated() {
            try SmartGroupRecord.filter(key: id)
                .updateAll(db, Column("sortOrder").set(to: index))
        }
    }

    // MARK: Collections

    /// `parentId` non-nil creates a CHILD collection (U41) — the caller passes
    /// the parent's `groupId`, children always live in their parent's group.
    @discardableResult
    public static func createCollection(
        name: String,
        inGroup groupId: Int64,
        parentId: Int64? = nil,
        matchAll: Bool = true,
        in db: Database
    ) throws -> SmartCollectionRecord {
        let maxOrder = try Int.fetchOne(
            db,
            sql: "SELECT MAX(sortOrder) FROM smartCollection WHERE groupId = ?",
            arguments: [groupId]
        ) ?? -1
        var record = SmartCollectionRecord(
            groupId: groupId, parentId: parentId, name: name,
            matchAll: matchAll, sortOrder: maxOrder + 1
        )
        try record.insert(db)
        return record
    }

    public static func updateCollection(_ collection: SmartCollectionRecord, in db: Database) throws {
        try collection.update(db)
    }

    public static func deleteCollection(_ id: Int64, in db: Database) throws {
        try SmartCollectionRecord.deleteOne(db, key: id)
    }

    public static func reorderCollections(_ orderedIds: [Int64], inGroup groupId: Int64, in db: Database) throws {
        for (index, id) in orderedIds.enumerated() {
            try SmartCollectionRecord.filter(key: id).updateAll(
                db,
                Column("sortOrder").set(to: index),
                Column("groupId").set(to: groupId)
            )
        }
    }

    // MARK: Rules

    /// Replaces a collection's rules wholesale — the editor sheet saves a copy (spec §9.7).
    public static func saveRules(
        _ rules: [(type: String, operation: String, value: String)],
        forCollection collectionId: Int64,
        in db: Database
    ) throws {
        try CollectionRuleRecord.filter(Column("collectionId") == collectionId).deleteAll(db)
        for (index, rule) in rules.enumerated() {
            var record = CollectionRuleRecord(
                collectionId: collectionId,
                type: rule.type,
                operation: rule.operation,
                value: rule.value,
                sortOrder: index
            )
            try record.insert(db)
        }
    }
}
