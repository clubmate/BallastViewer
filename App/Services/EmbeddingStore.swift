import Foundation
import GRDB

/// U48: sidecar cache for photo image embeddings — deliberately NOT in
/// library.sqlite (regenerable derived data, like thumbnails; keeps the
/// library file lean and the WritePipeline contract untouched). One SQLite
/// file per library under Caches/Embeddings/, keyed path + mtime + model
/// version, so a rewritten file or a model upgrade re-embeds naturally.
actor EmbeddingStore {
    private let dbQueue: DatabaseQueue

    init(libraryUUID: String) throws {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches.appendingPathComponent("Embeddings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(libraryUUID).sqlite")
        dbQueue = try DatabaseQueue(path: url.path)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE IF NOT EXISTS imageEmbedding (
                        path TEXT PRIMARY KEY,
                        mtime INTEGER NOT NULL,
                        modelVersion TEXT NOT NULL,
                        vector BLOB NOT NULL
                    )
                    """
            )
        }
    }

    func embedding(forPath path: String, mtime: Int, modelVersion: String) throws -> [Float]? {
        try dbQueue.read { db in
            guard let data = try Data.fetchOne(
                db,
                sql: "SELECT vector FROM imageEmbedding WHERE path = ? AND mtime = ? AND modelVersion = ?",
                arguments: [path, mtime, modelVersion]
            ) else { return nil }
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
    }

    /// Whole-second file mtime — the freshness half of the cache key.
    nonisolated static func mtime(of path: String) -> Int {
        let date = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate])
            as? Date
        return Int(date?.timeIntervalSince1970 ?? 0)
    }

    func store(_ vector: [Float], forPath path: String, mtime: Int, modelVersion: String) throws {
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO imageEmbedding (path, mtime, modelVersion, vector)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET mtime = ?, modelVersion = ?, vector = ?
                    """,
                arguments: [path, mtime, modelVersion, data, mtime, modelVersion, data]
            )
        }
    }
}
