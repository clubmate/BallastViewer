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

    /// U35: moves a keyword (subtree included) to the TOP LEVEL of `groupId`
    /// — the escape hatch for imported Lightroom hierarchies ("JAHRE > 2008"
    /// → top-level "2008" in the YEAR group). A same-named top-level keyword
    /// absorbs the moved one instead of colliding: photo assignments union,
    /// same-named children merge recursively, the source node is deleted.
    /// Returns the surviving top-level id.
    @discardableResult
    public static func moveToTopLevel(_ id: Int64, groupId: Int64?, in db: Database) throws -> Int64 {
        guard let node = try KeywordRecord.fetchOne(db, key: id) else { return id }
        let twin = try KeywordRecord
            .filter(Column("parentId") == nil && Column("name") == node.name && Column("id") != id)
            .fetchOne(db)
        if let twin, let twinId = twin.id {
            try merge(id, into: twinId, in: db)
            try KeywordRecord.filter(key: twinId)
                .updateAll(db, Column("groupId").set(to: groupId))
            return twinId
        }
        try KeywordRecord.filter(key: id).updateAll(
            db,
            Column("parentId").set(to: nil as Int64?),
            Column("groupId").set(to: groupId)
        )
        return id
    }

    /// Folds `sourceId` into `targetId`: assignments union (idempotent),
    /// same-named children merge recursively, the rest re-hang under the
    /// target; the source row is deleted (FK cascade drops its assignments).
    /// Public for the rename-collision path (U40): renaming "_STRASSE" next
    /// to an existing sibling "STRASSE" merges into it instead of failing.
    public static func merge(_ sourceId: Int64, into targetId: Int64, in db: Database) throws {
        guard sourceId != targetId else { return }
        // A target inside the source's subtree would re-hang an ancestor
        // under its own descendant — refuse instead of corrupting the tree.
        var cursor = try KeywordRecord.fetchOne(db, key: targetId)?.parentId
        while let current = cursor {
            guard current != sourceId else { throw KeywordDAOError.mergeTargetInsideSource }
            cursor = try KeywordRecord.fetchOne(db, key: current)?.parentId
        }
        try mergeUnchecked(sourceId, into: targetId, in: db)
    }

    private static func mergeUnchecked(_ sourceId: Int64, into targetId: Int64, in db: Database) throws {
        // Assignments keep their U48 status; where source and target disagree
        // a confirmed row wins over a pending suggestion.
        try db.execute(
            sql: """
                INSERT INTO photoKeyword (photoId, keywordId, status)
                SELECT photoId, ?, status FROM photoKeyword WHERE keywordId = ?
                ON CONFLICT(photoId, keywordId) DO UPDATE SET status = 'confirmed'
                    WHERE excluded.status = 'confirmed' AND status = 'pending'
                """,
            arguments: [targetId, sourceId]
        )
        // Rejection memory (U48) survives the merge — without this the FK
        // cascade on the source row would forget the user's rejections.
        try db.execute(
            sql: """
                INSERT OR IGNORE INTO rejectedSuggestion (photoId, keywordId)
                SELECT photoId, ? FROM rejectedSuggestion WHERE keywordId = ?
                """,
            arguments: [targetId, sourceId]
        )
        // U49: profile answers pointing at the source follow it into the
        // survivor — a merge must not silently unmap auto-tagging setup.
        try db.execute(
            sql: "UPDATE aiAnswer SET keywordId = ? WHERE keywordId = ?",
            arguments: [targetId, sourceId]
        )
        try db.execute(
            sql: "UPDATE aiQuestion SET parentKeywordId = ? WHERE parentKeywordId = ?",
            arguments: [targetId, sourceId]
        )
        let children = try KeywordRecord.filter(Column("parentId") == sourceId).fetchAll(db)
        for child in children {
            guard let childId = child.id else { continue }
            if let twin = try KeywordRecord
                .filter(Column("parentId") == targetId && Column("name") == child.name)
                .fetchOne(db), let twinId = twin.id
            {
                try mergeUnchecked(childId, into: twinId, in: db)
            } else {
                try KeywordRecord.filter(key: childId)
                    .updateAll(db, Column("parentId").set(to: targetId))
            }
        }
        try KeywordRecord.deleteOne(db, key: sourceId)
    }

    // MARK: Coined keywords (U50)

    /// Finds the child of `parentId` (nil = top level) named `name`, or
    /// creates it flagged `aiCreated`. Returns the id and the record when a
    /// row was inserted (for the in-memory tree delta).
    public static func ensureChild(
        named rawName: String, parentId: Int64?, aiCreated: Bool, in db: Database
    ) throws -> (id: Int64, created: KeywordRecord?) {
        let name = normalize(rawName)
        guard !name.isEmpty else { throw KeywordDAOError.emptyName }
        let parentFilter: SQLExpression =
            parentId == nil ? Column("parentId") == nil : Column("parentId") == parentId
        if let existing = try KeywordRecord.filter(parentFilter && Column("name") == name).fetchOne(db),
           let id = existing.id {
            return (id, nil)
        }
        var record = KeywordRecord(parentId: parentId, groupId: nil, name: name, aiCreated: aiCreated)
        try record.insert(db)
        return (record.id!, record)
    }

    /// Among `candidates`, the coined keywords nothing holds on to any more:
    /// no assignment (confirmed OR pending), no child, no questionnaire
    /// referencing them. Deleted by the caller — with their rejection
    /// tombstones, which is why coined rejections are ALSO kept by path.
    public static func orphanedAIKeywords(among candidates: Set<Int64>, in db: Database) throws -> [KeywordRecord] {
        guard !candidates.isEmpty else { return [] }
        let referenced = try AIProfileDAO.referencedKeywordIds(db)
        var orphans: [KeywordRecord] = []
        for id in candidates.subtracting(referenced) {
            guard let record = try KeywordRecord.fetchOne(db, key: id), record.aiCreated else { continue }
            let carriers = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photoKeyword WHERE keywordId = ?", arguments: [id]) ?? 0
            guard carriers == 0 else { continue }
            let children = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM keyword WHERE parentId = ?", arguments: [id]) ?? 0
            guard children == 0 else { continue }
            orphans.append(record)
        }
        return orphans
    }

    /// Re-inserts collected keywords under their old ids (undo of a reject
    /// or discard that collected them). Rows that came back some other way
    /// in the meantime are left alone.
    public static func restore(_ records: [KeywordRecord], in db: Database) throws {
        for record in records {
            guard let id = record.id, try KeywordRecord.fetchOne(db, key: id) == nil else { continue }
            var copy = record
            try copy.insert(db)
        }
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
    /// Merging a node into its own descendant would re-hang an ancestor
    /// under its child and turn the tree into a cycle.
    case mergeTargetInsideSource
}
