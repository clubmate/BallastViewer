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

        migrator.registerMigration("v4-needsFileWrite") { db in
            // Dirty flag of the automatic metadata write-through: set with
            // every rating/keyword change, cleared once the file carries the
            // values. Survives a crash so the next open finishes the writes.
            try db.alter(table: "photo") { t in
                t.add(column: "needsFileWrite", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v5-library-name") { db in
            // User-editable display name (Settings ▸ Libraries). NULL means
            // "no name set" — the UI falls back to the package filename.
            try db.alter(table: "libraryMeta") { t in
                t.add(column: "name", .text)
            }
        }

        migrator.registerMigration("v6-collection-parent") { db in
            // U41: child Smart Collections. NULL = top level; deleting a
            // parent cascades through its subtree.
            try db.alter(table: "smartCollection") { t in
                t.add(column: "parentId", .integer)
                    .references("smartCollection", onDelete: .cascade)
            }
            try db.create(
                index: "smartCollection_parentId", on: "smartCollection", columns: ["parentId"]
            )
        }

        migrator.registerMigration("v7-lightroom-merged") { db in
            // U43: when a Lightroom import covered a photo (even as a no-op),
            // the run's date lands here. Later imports skip flagged photos so
            // keywords the user reorganized since are not re-created at their
            // old Lightroom paths. NULL = never covered by an import.
            try db.alter(table: "photo") { t in
                t.add(column: "lightroomMergedAt", .datetime)
            }
        }

        migrator.registerMigration("v8-ai-suggestions") { db in
            // U48: short English description driving the MobileCLIP text
            // embedding. NULL = keyword opted out of AI suggestions entirely.
            try db.alter(table: "keyword") { t in
                t.add(column: "aiDescription", .text)
            }
            // U48: 'confirmed' | 'pending'. Pending = AI suggestion awaiting
            // review — never file-written, never a query fact.
            try db.alter(table: "photoKeyword") { t in
                t.add(column: "status", .text).notNull().defaults(to: "confirmed")
            }
            // U48: rejected suggestions, remembered so re-runs skip them.
            // Deliberately NOT a photoKeyword status: a tombstone row there
            // would occupy the PK and swallow later manual assignments.
            try db.create(table: "rejectedSuggestion", options: [.withoutRowID]) { t in
                t.column("photoId", .integer).notNull()
                    .references("photo", onDelete: .cascade)
                t.column("keywordId", .integer).notNull()
                    .references("keyword", onDelete: .cascade)
                t.primaryKey(["photoId", "keywordId"])
            }
            try db.create(
                index: "rejectedSuggestion_keywordId", on: "rejectedSuggestion", columns: ["keywordId"]
            )
        }

        migrator.registerMigration("v9-ai-profiles") { db in
            // U49: the vision-language model replaced CLIP. Keywords no longer
            // carry a prompt — auto-tagging is driven by PROFILES (a
            // questionnaire per photo genre) whose answers map to keywords.
            // The old per-keyword prompts are not thrown away: they land,
            // read-only, in the instructions of a DISABLED profile so the
            // user can lift the wording into real questions.
            let descriptions = try Row.fetchAll(
                db, sql: "SELECT name, aiDescription FROM keyword WHERE aiDescription IS NOT NULL ORDER BY name"
            )
            try db.alter(table: "keyword") { t in
                t.drop(column: "aiDescription")
            }
            try db.create(table: "aiProfile") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("position", .integer).notNull().defaults(to: 0)
                t.column("instructions", .text).notNull().defaults(to: "")
            }
            try db.create(table: "aiQuestion") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("profileId", .integer).notNull()
                    .references("aiProfile", onDelete: .cascade)
                t.column("position", .integer).notNull().defaults(to: 0)
                t.column("text", .text).notNull()
            }
            try db.create(table: "aiAnswer") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("questionId", .integer).notNull()
                    .references("aiQuestion", onDelete: .cascade)
                t.column("position", .integer).notNull().defaults(to: 0)
                t.column("value", .text).notNull()
                // A deleted keyword leaves the answer in place, unmapped.
                t.column("keywordId", .integer)
                    .references("keyword", onDelete: .setNull)
                // Chosen → the remaining questions of the profile assign
                // nothing for this photo ("no person" ends the questionnaire).
                t.column("stopsProfile", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "aiQuestion_profileId", on: "aiQuestion", columns: ["profileId"])
            try db.create(index: "aiAnswer_questionId", on: "aiAnswer", columns: ["questionId"])
            try db.create(index: "aiAnswer_keywordId", on: "aiAnswer", columns: ["keywordId"])
            if !descriptions.isEmpty {
                let lines = descriptions.map { row -> String in
                    "\(row["name"] as String): \(row["aiDescription"] as String)"
                }
                try db.execute(
                    sql: "INSERT INTO aiProfile (name, enabled, position, instructions) VALUES (?, 0, 0, ?)",
                    arguments: [
                        "Imported prompts (old CLIP setup)",
                        "These were the keyword descriptions of the previous CLIP-based auto-tagging, kept for reference. Turn them into questions with fixed answers, or delete this questionnaire.\n\n"
                            + lines.joined(separator: "\n"),
                    ]
                )
            }
        }

        migrator.registerMigration("v10-ai-branching") { db in
            // U50: questions form a TREE — a follow-up question hangs off one
            // answer of an earlier question and is asked only when that
            // answer was chosen. Deleted with the parent answer (cascade).
            // `kind`: 'choice' (pick one allowed answer) or 'open' (the
            // model's own words become a keyword — created on demand under
            // `parentKeywordId`, or at the top level when NULL).
            try db.alter(table: "aiQuestion") { t in
                t.add(column: "parentAnswerId", .integer)
                    .references("aiAnswer", onDelete: .cascade)
                t.add(column: "kind", .text).notNull().defaults(to: "choice")
                t.add(column: "parentKeywordId", .integer)
                    .references("keyword", onDelete: .setNull)
            }
            try db.create(index: "aiQuestion_parentAnswerId", on: "aiQuestion", columns: ["parentAnswerId"])
            try db.create(index: "aiQuestion_parentKeywordId", on: "aiQuestion", columns: ["parentKeywordId"])
            // Keywords the model coined (open answers). They are garbage-
            // collected once nothing carries or references them any more —
            // a rejected coinage must not linger in the tree.
            try db.alter(table: "keyword") { t in
                t.add(column: "aiCreated", .boolean).notNull().defaults(to: false)
            }
            // Rejection memory for coined keywords, keyed by PATH: the
            // keyword row itself may be collected after the rejection, and a
            // later run coining the same words must still skip the photo.
            try db.create(table: "rejectedAIAnswer", options: [.withoutRowID]) { t in
                t.column("photoId", .integer).notNull()
                    .references("photo", onDelete: .cascade)
                t.column("keywordPath", .text).notNull()
                t.primaryKey(["photoId", "keywordPath"])
            }
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
