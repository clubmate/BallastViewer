import Foundation
import GRDB

/// U49: sidecar cache of the model's raw replies — deliberately NOT in
/// library.sqlite (regenerable derived data, like thumbnails). One SQLite
/// file per library under Caches/AIAnswers/, keyed by photo path + mtime,
/// model and the questionnaire's fingerprint. A re-run over reviewed photos,
/// or after re-mapping an answer to another keyword, costs no inference.
actor AIAnswerStore {
    private let dbQueue: DatabaseQueue

    nonisolated static func open(libraryUUID: String) async throws -> AIAnswerStore {
        // Directory creation + CREATE TABLE are disk I/O — off the caller's
        // executor (the run starts on the MainActor).
        try await Task.detached(priority: .utility) { try AIAnswerStore(libraryUUID: libraryUUID) }.value
    }

    /// The metadata write-through rewrites the image file (metadata only,
    /// pixels untouched) and thereby bumps its mtime — the cached replies
    /// are still valid, so their key follows the file instead of expiring.
    nonisolated static func fileRewritten(paths: [String], libraryUUID: String) async {
        guard let store = try? await open(libraryUUID: libraryUUID) else { return }
        for path in paths {
            try? await store.rekey(path: path, mtime: mtime(of: path))
        }
    }

    func rekey(path: String, mtime: Int) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE reply SET mtime = ? WHERE path = ?", arguments: [mtime, path])
        }
    }

    private init(libraryUUID: String) throws {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches.appendingPathComponent("AIAnswers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: directory.appendingPathComponent("\(libraryUUID).sqlite").path)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE IF NOT EXISTS reply (
                        path TEXT NOT NULL,
                        mtime INTEGER NOT NULL,
                        modelId TEXT NOT NULL,
                        questionnaire TEXT NOT NULL,
                        reply TEXT NOT NULL,
                        PRIMARY KEY (path, modelId, questionnaire)
                    )
                    """
            )
        }
    }

    func reply(forPath path: String, mtime: Int, modelId: String, questionnaire: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT reply FROM reply WHERE path = ? AND mtime = ? AND modelId = ? AND questionnaire = ?",
                arguments: [path, mtime, modelId, questionnaire]
            )
        }
    }

    func store(_ reply: String, forPath path: String, mtime: Int, modelId: String, questionnaire: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO reply (path, mtime, modelId, questionnaire, reply) VALUES (?, ?, ?, ?, ?)",
                arguments: [path, mtime, modelId, questionnaire, reply]
            )
        }
    }

    /// Whole-second file mtime — the freshness half of the cache key.
    nonisolated static func mtime(of path: String) -> Int {
        let date = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        return Int(date?.timeIntervalSince1970 ?? 0)
    }
}
