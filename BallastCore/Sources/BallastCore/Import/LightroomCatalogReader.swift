import Foundation
import GRDB

/// One photo as a Lightroom Classic catalog describes it: the absolute file
/// path Lightroom last saw, the star rating, and every hierarchical keyword
/// assigned to it (root-first components, verbatim from the catalog — the
/// merge normalizes them to the UPPERCASE storage invariant).
public struct LightroomPhotoEntry: Sendable, Equatable {
    public var path: String
    /// nil = unrated in Lightroom; the merge then leaves the library rating alone.
    public var rating: Int?
    public var keywordPaths: [[String]]

    public init(path: String, rating: Int? = nil, keywordPaths: [[String]] = []) {
        self.path = path
        self.rating = rating
        self.keywordPaths = keywordPaths
    }
}

public enum LightroomCatalogError: Error, LocalizedError {
    /// The file opened as SQLite but lacks the Lightroom tables.
    case notALightroomCatalog

    public var errorDescription: String? {
        switch self {
        case .notALightroomCatalog:
            return "The file does not look like a Lightroom Classic catalog."
        }
    }
}

/// Reads photos, ratings and keyword hierarchies out of a Lightroom Classic
/// catalog — an `.lrcat` file is itself a SQLite database. Read-only in
/// intent, but the connection opens read-write so a copied-over WAL sidecar
/// can be recovered: callers should hand in a COPY of the catalog, never the
/// live file Lightroom may have open.
public enum LightroomCatalogReader {
    public static func read(at url: URL) throws -> [LightroomPhotoEntry] {
        let dbQueue = try DatabaseQueue(path: url.path)
        defer { try? dbQueue.close() }
        return try dbQueue.read(entries(in:))
    }

    private static func entries(in db: Database) throws -> [LightroomPhotoEntry] {
        for table in [
            "AgLibraryRootFolder", "AgLibraryFolder", "AgLibraryFile",
            "Adobe_images", "AgLibraryKeyword", "AgLibraryKeywordImage",
        ] where try !db.tableExists(table) {
            throw LightroomCatalogError.notALightroomCatalog
        }

        // Folder tree → absolute path per AgLibraryFile row. Lightroom stores
        // `absolutePath` and `pathFromRoot` with trailing slashes; guard anyway.
        var rootPaths: [Int64: String] = [:]
        var cursor = try Row.fetchCursor(
            db, sql: "SELECT id_local, absolutePath FROM AgLibraryRootFolder"
        )
        while let row = try cursor.next() {
            guard let path = row[1] as String? else { continue }
            rootPaths[row[0]] = path.hasSuffix("/") ? path : path + "/"
        }
        var folderPaths: [Int64: String] = [:]
        cursor = try Row.fetchCursor(
            db, sql: "SELECT id_local, rootFolder, pathFromRoot FROM AgLibraryFolder"
        )
        while let row = try cursor.next() {
            guard let root = rootPaths[row[1] as Int64] else { continue }
            let fromRoot = (row[2] as String?) ?? ""
            let combined = root + fromRoot
            folderPaths[row[0]] = combined.hasSuffix("/") || fromRoot.isEmpty
                ? combined : combined + "/"
        }
        var filePaths: [Int64: String] = [:]
        cursor = try Row.fetchCursor(
            db, sql: "SELECT id_local, folder, idx_filename FROM AgLibraryFile"
        )
        while let row = try cursor.next() {
            guard let folder = folderPaths[row[1] as Int64],
                  let filename = row[2] as String?, !filename.isEmpty
            else { continue }
            filePaths[row[0]] = folder + filename
        }

        // Keyword tree: the invisible root row has a NULL name and is skipped
        // when assembling path components. Depth-capped against a corrupt
        // catalog's parent cycle.
        struct KeywordNode { var parent: Int64?; var name: String? }
        var keywordNodes: [Int64: KeywordNode] = [:]
        cursor = try Row.fetchCursor(
            db, sql: "SELECT id_local, parent, name FROM AgLibraryKeyword"
        )
        while let row = try cursor.next() {
            keywordNodes[row[0]] = KeywordNode(parent: row[1] as Int64?, name: row[2] as String?)
        }
        var componentsByKeyword: [Int64: [String]] = [:]
        func pathComponents(of keywordId: Int64) -> [String] {
            if let memo = componentsByKeyword[keywordId] { return memo }
            var components: [String] = []
            var current: Int64? = keywordId
            var depth = 0
            while let id = current, let node = keywordNodes[id], depth < 64 {
                if let name = node.name,
                   !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    components.append(name)
                }
                current = node.parent
                depth += 1
            }
            let result = Array(components.reversed())
            componentsByKeyword[keywordId] = result
            return result
        }

        var tagsByImage: [Int64: [Int64]] = [:]
        cursor = try Row.fetchCursor(
            db, sql: "SELECT image, tag FROM AgLibraryKeywordImage"
        )
        while let row = try cursor.next() {
            tagsByImage[row[0], default: []].append(row[1])
        }

        // One entry per FILE, aggregated across its Adobe_images rows: virtual
        // copies share the file, so keywords union and the best rating wins.
        struct FileAggregate { var rating: Int?; var keywordIds: [Int64] = [] }
        var aggregates: [Int64: FileAggregate] = [:]
        cursor = try Row.fetchCursor(
            db, sql: "SELECT id_local, rootFile, rating FROM Adobe_images"
        )
        while let row = try cursor.next() {
            let imageId: Int64 = row[0]
            let fileId: Int64 = row[1]
            var aggregate = aggregates[fileId] ?? FileAggregate(rating: nil)
            if let raw = row[2] as Double? {
                let rating = max(0, min(5, Int(raw.rounded())))
                aggregate.rating = max(aggregate.rating ?? 0, rating)
            }
            for tag in tagsByImage[imageId] ?? [] where !aggregate.keywordIds.contains(tag) {
                aggregate.keywordIds.append(tag)
            }
            aggregates[fileId] = aggregate
        }

        var entries: [LightroomPhotoEntry] = []
        entries.reserveCapacity(aggregates.count)
        for (fileId, aggregate) in aggregates.sorted(by: { $0.key < $1.key }) {
            guard let path = filePaths[fileId] else { continue }
            let keywordPaths = aggregate.keywordIds
                .map(pathComponents(of:))
                .filter { !$0.isEmpty }
            entries.append(LightroomPhotoEntry(
                path: path, rating: aggregate.rating, keywordPaths: keywordPaths
            ))
        }
        return entries
    }
}
