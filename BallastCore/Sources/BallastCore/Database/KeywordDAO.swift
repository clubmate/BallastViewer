import Foundation
import GRDB

/// Per-transaction memo for `KeywordDAO.ensurePath`: `(parentId, name) → id`.
/// Bulk callers (import, metadata sync) resolve the same few hundred nodes
/// tens of thousands of times; without the memo each component costs a SELECT
/// inside the writer transaction. Scope it to ONE transaction — ids from a
/// rolled-back transaction must not leak into the next.
public final class KeywordPathCache {
    private struct Key: Hashable { let parentId: Int64?; let name: String }
    private var idByKey: [Key: Int64] = [:]

    public init() {}

    /// Pre-seeds the memo with every existing node, so a bulk run starts with
    /// zero lookups instead of one per distinct node.
    public init(preloading db: Database) throws {
        for record in try KeywordRecord.fetchAll(db) {
            guard let id = record.id else { continue }
            idByKey[Key(parentId: record.parentId, name: record.name)] = id
        }
    }

    fileprivate func id(parentId: Int64?, name: String) -> Int64? {
        idByKey[Key(parentId: parentId, name: name)]
    }

    fileprivate func remember(parentId: Int64?, name: String, id: Int64) {
        idByKey[Key(parentId: parentId, name: name)] = id
    }
}

public enum KeywordDAO {
    /// Normalises a keyword component to the storage invariant: trimmed,
    /// UPPERCASE, NFC. The precomposition matters because SQLite compares
    /// bytes: a decomposed "MÜNCHEN" from an XMP file would otherwise create a
    /// visually identical duplicate row next to a typed, precomposed one.
    public static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .precomposedStringWithCanonicalMapping
    }

    /// Finds or creates the node chain for the given path components and returns
    /// the leaf's id. Created nodes get `groupId` (children created through the UI
    /// inherit their parent's group, matching the original's behaviour, spec §3.8).
    @discardableResult
    public static func ensurePath(
        _ components: [String],
        groupId: Int64?,
        cache: KeywordPathCache? = nil,
        in db: Database
    ) throws -> Int64 {
        try ensurePathCollectingCreated(components, groupId: groupId, cache: cache, in: db).leafId
    }

    /// Like `ensurePath`, but reports the records it actually inserted — the
    /// caller can then derive the new in-memory tree without re-fetching the
    /// whole keyword table.
    public static func ensurePathCollectingCreated(
        _ components: [String],
        groupId: Int64?,
        cache: KeywordPathCache? = nil,
        in db: Database
    ) throws -> (leafId: Int64, created: [KeywordRecord]) {
        // Malformed input like "A >  > B" must not create a node with an empty
        // name mid-path (KeywordResolver filters the same way).
        let names = components.map(normalize).filter { !$0.isEmpty }
        guard !names.isEmpty else { throw KeywordDAOError.emptyName }
        var created: [KeywordRecord] = []
        var parentId: Int64? = nil
        var currentId: Int64 = 0
        for name in names {
            if let cached = cache?.id(parentId: parentId, name: name) {
                currentId = cached
            } else {
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
                    created.append(record)
                    currentId = record.id!
                }
                cache?.remember(parentId: parentId, name: name, id: currentId)
            }
            parentId = currentId
        }
        return (currentId, created)
    }

    /// One UPDATE — every photo carrying this keyword (or a descendant) reflects
    /// the new derived path immediately (fixes C4).
    public static func rename(_ id: Int64, to newName: String, in db: Database) throws {
        let name = normalize(newName)
        guard !name.isEmpty else { throw KeywordDAOError.emptyName }
        try KeywordRecord.filter(key: id)
            .updateAll(db, Column("name").set(to: name))
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
        var record = KeywordGroupRecord(name: normalize(name), color: color, sortOrder: maxOrder + 1)
        try record.insert(db)
        return record
    }

    /// Members become ad-hoc keywords (groupId NULL via FK) instead of orphans (fixes C3).
    public static func deleteGroup(_ id: Int64, in db: Database) throws {
        try KeywordGroupRecord.deleteOne(db, key: id)
    }

    public static func renameGroup(_ id: Int64, to name: String, in db: Database) throws {
        let normalized = normalize(name)
        guard !normalized.isEmpty else { throw KeywordDAOError.emptyName }
        try KeywordGroupRecord.filter(key: id)
            .updateAll(db, Column("name").set(to: normalized))
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

public enum KeywordDAOError: Error, Equatable, Sendable {
    /// A blank name would persist as `""` and produce paths like `PEOPLE > `
    /// that `KeywordResolver` can never address again.
    case emptyName
}
