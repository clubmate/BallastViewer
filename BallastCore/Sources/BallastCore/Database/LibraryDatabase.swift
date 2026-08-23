import Foundation
import GRDB

public enum LibraryDatabaseError: Error, LocalizedError, Equatable {
    case alreadyExists(URL)
    case notALibrary(URL)

    public var errorDescription: String? {
        switch self {
        case .alreadyExists(let url):
            "A file or folder already exists at \(url.path)."
        case .notALibrary(let url):
            "\(url.lastPathComponent) is not a BallastViewer library."
        }
    }
}

/// A library on disk: a document package directory `Name.ballastlib/`
/// containing `library.sqlite` (WAL journal lives alongside, inside the package).
public struct LibraryDatabase: Sendable {
    public static let packageExtension = "ballastlib"
    static let databaseFilename = "library.sqlite"

    public let packageURL: URL
    public let pool: DatabasePool

    /// Creates a new library package, migrates it to the current schema and seeds
    /// the defaults. Fails if anything already exists at `url`.
    public static func create(at url: URL) throws -> LibraryDatabase {
        if FileManager.default.fileExists(atPath: url.path) {
            throw LibraryDatabaseError.alreadyExists(url)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        do {
            let pool = try makePool(in: url)
            try LibrarySchema.migrator.migrate(pool)
            try pool.write { try LibrarySchema.seed($0) }
            return LibraryDatabase(packageURL: url, pool: pool)
        } catch {
            // A half-created package would make every retry fail with
            // `alreadyExists`; remove what we just created before rethrowing.
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Opens an existing library package and migrates it forward if needed.
    public static func open(at url: URL) throws -> LibraryDatabase {
        let dbURL = url.appendingPathComponent(databaseFilename)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.fileExists(atPath: dbURL.path)
        else {
            throw LibraryDatabaseError.notALibrary(url)
        }
        let pool = try makePool(in: url)
        try LibrarySchema.migrator.migrate(pool)
        return LibraryDatabase(packageURL: url, pool: pool)
    }

    private static func makePool(in packageURL: URL) throws -> DatabasePool {
        let dbURL = packageURL.appendingPathComponent(databaseFilename)
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try DatabasePool(path: dbURL.path, configuration: config)
    }
}
