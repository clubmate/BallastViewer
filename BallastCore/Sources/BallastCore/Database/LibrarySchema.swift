import Foundation
import GRDB

/// Schema v1. All schema changes go through new named migrations — never edit "v1".
public enum LibrarySchema {
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // Referenced tables must exist before their referents — GRDB resolves
            // the referenced primary key when generating the DDL.
            try db.create(table: "folder") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("path", .text).notNull().unique()
                t.column("bookmark", .blob)
                t.column("recursive", .boolean).notNull().defaults(to: true)
                t.column("dateAdded", .datetime).notNull()
            }

            try db.create(table: "importBatch") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .datetime).notNull()
            }

            try db.create(table: "libraryMeta") { t in
                t.primaryKey("id", .integer).check { $0 == 1 }
                t.column("libraryUUID", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastImportBatchId", .integer)
                    .references("importBatch", onDelete: .setNull)
                t.column("selectedCollection", .text)
                t.column("collapsedGroups", .text).notNull().defaults(to: "[]")
            }

            try db.create(table: "photo") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("folder", onDelete: .cascade).notNull()
                t.column("path", .text).notNull().unique()
                t.column("filename", .text).notNull()
                t.column("rating", .integer).notNull().defaults(to: 0)
                    .check { $0 >= 0 && $0 <= 5 }
                t.column("orientation", .integer).notNull().defaults(to: 1)
                t.column("captureDate", .datetime)
                t.column("dateAdded", .datetime).notNull()
                t.belongsTo("importBatch", onDelete: .setNull)
            }
            try db.create(index: "photo_rating", on: "photo", columns: ["rating"])

            try db.create(table: "keywordGroup") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("color", .text).notNull()
                t.column("sortOrder", .integer).notNull()
            }

            try db.create(table: "keyword") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("parentId", .integer)
                    .references("keyword", onDelete: .cascade)
                t.column("groupId", .integer)
                    .references("keywordGroup", onDelete: .setNull)
                t.column("name", .text).notNull()
                // Sibling names are unique below a parent…
                t.uniqueKey(["parentId", "name"])
            }
            // …and SQLite treats NULLs as distinct, so top level needs its own index.
            try db.create(
                index: "keyword_topLevel_name",
                on: "keyword",
                columns: ["name"],
                options: [.unique],
                condition: Column("parentId") == nil
            )
            try db.create(index: "keyword_parentId", on: "keyword", columns: ["parentId"])
            try db.create(index: "keyword_groupId", on: "keyword", columns: ["groupId"])

            try db.create(table: "photoKeyword", options: [.withoutRowID]) { t in
                t.column("photoId", .integer).notNull()
                    .references("photo", onDelete: .cascade)
                t.column("keywordId", .integer).notNull()
                    .references("keyword", onDelete: .cascade)
                t.primaryKey(["photoId", "keywordId"])
            }
            try db.create(index: "photoKeyword_keywordId", on: "photoKeyword", columns: ["keywordId"])

            try db.create(table: "smartGroup") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("sortOrder", .integer).notNull()
            }

            try db.create(table: "smartCollection") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("groupId", .integer).notNull()
                    .references("smartGroup", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("matchAll", .boolean).notNull().defaults(to: true)
                t.column("sortOrder", .integer).notNull()
            }
            try db.create(index: "smartCollection_groupId", on: "smartCollection", columns: ["groupId"])

            try db.create(table: "collectionRule") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("collectionId", .integer).notNull()
                    .references("smartCollection", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("operation", .text).notNull()
                t.column("value", .text).notNull()
                t.column("sortOrder", .integer).notNull()
            }
            try db.create(index: "collectionRule_collectionId", on: "collectionRule", columns: ["collectionId"])
        }

        migrator.registerMigration("v2-fk-indexes") { db in
            // FK columns SQLite consults on cascade/setNull: without these a
            // folder removal or batch deletion scans the whole photo table.
            try db.create(index: "photo_folderId", on: "photo", columns: ["folderId"])
            try db.create(index: "photo_importBatchId", on: "photo", columns: ["importBatchId"])
        }

        migrator.registerMigration("v3-drop-rating-index") { db in
            // No query ever filters on rating in SQL (rating filters run
            // in-memory by design), but every rating write — the hottest write
            // path — maintained this B-tree.
            try db.drop(index: "photo_rating")
        }

        return migrator
    }

    /// Seeds a freshly migrated database: the singleton meta row and the six
    /// default keyword groups (spec §8.3). Call exactly once, at library creation.
    public static func seed(_ db: Database) throws {
        try LibraryMetaRecord().insert(db)
        for (index, group) in KeywordGroupRecord.defaults.enumerated() {
            var record = KeywordGroupRecord(name: group.name, color: group.color, sortOrder: index)
            try record.insert(db)
        }
    }
}
