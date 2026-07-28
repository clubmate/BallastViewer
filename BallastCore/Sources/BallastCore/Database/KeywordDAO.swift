import Foundation
import GRDB

public enum KeywordDAO {
    /// Normalises a keyword component to the storage invariant: trimmed, UPPERCASE.
    public static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Finds or creates the node chain for the given path components and returns
    /// the leaf's id. Created nodes get `groupId` (children created through the UI
    /// inherit their parent's group, matching the original's behaviour, spec §3.8).
    @discardableResult
    public static func ensurePath(
        _ components: [String],
        groupId: Int64?,
        in db: Database
    ) throws -> Int64 {
        precondition(!components.isEmpty, "ensurePath needs at least one component")
        var parentId: Int64? = nil
        var currentId: Int64 = 0
        for rawName in components {
            let name = normalize(rawName)
            let parentFilter: SQLExpression =
                parentId == nil ? Column("parentId") == nil : Column("parentId") == parentId
            if let existing = try KeywordRecord
                .filter(parentFilter && Column("name") == name)
                .fetchOne(db),
                let existingId = existing.id
            {
                currentId = existingId
            } else {
                var record = KeywordRecord(parentId: parentId, groupId: groupId, name: name)
                try record.insert(db)
                currentId = record.id!
            }
            parentId = currentId
        }
        return currentId
    }

    /// One UPDATE — every photo carrying this keyword (or a descendant) reflects
    /// the new derived path immediately (fixes C4).
    public static func rename(_ id: Int64, to newName: String, in db: Database) throws {
        try KeywordRecord.filter(key: id)
            .updateAll(db, Column("name").set(to: normalize(newName)))
    }

    /// Deletes the node and its entire subtree (FK cascade), including all
    /// photo assignments (spec §8.6).
    public static func deleteSubtree(_ id: Int64, in db: Database) throws {
        try KeywordRecord.deleteOne(db, key: id)
    }

    public static func setGroup(_ groupId: Int64?, forKeywordId id: Int64, in db: Database) throws {
        try KeywordRecord.filter(key: id)
            .updateAll(db, Column("groupId").set(to: groupId))
    }

    public static func fetchAll(_ db: Database) throws -> [KeywordRecord] {
        try KeywordRecord.fetchAll(db)
    }

    // MARK: Groups

    @discardableResult
    public static func createGroup(name: String, color: String, in db: Database) throws -> KeywordGroupRecord {
        let maxOrder = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM keywordGroup") ?? -1
        var record = KeywordGroupRecord(name: name, color: color, sortOrder: maxOrder + 1)
        try record.insert(db)
        return record
    }

    /// Members become ad-hoc keywords (groupId NULL via FK) instead of orphans (fixes C3).
    public static func deleteGroup(_ id: Int64, in db: Database) throws {
        try KeywordGroupRecord.deleteOne(db, key: id)
    }

    public static func renameGroup(_ id: Int64, to name: String, in db: Database) throws {
        try KeywordGroupRecord.filter(key: id)
            .updateAll(db, Column("name").set(to: normalize(name)))
    }

    public static func setGroupColor(_ id: Int64, color: String, in db: Database) throws {
        try KeywordGroupRecord.filter(key: id)
            .updateAll(db, Column("color").set(to: color))
    }

    public static func fetchGroups(_ db: Database) throws -> [KeywordGroupRecord] {
        try KeywordGroupRecord.order(Column("sortOrder")).fetchAll(db)
    }

    /// Persists a user drag-reorder: `orderedIds` in the new display order.
    public static func reorderGroups(_ orderedIds: [Int64], in db: Database) throws {
        for (index, id) in orderedIds.enumerated() {
            try KeywordGroupRecord.filter(key: id)
                .updateAll(db, Column("sortOrder").set(to: index))
        }
    }
}
