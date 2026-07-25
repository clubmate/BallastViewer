import Foundation
import GRDB

public struct FolderRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "folder"

    public var id: Int64?
    /// Absolute folder path. Unique — re-adding a registered folder rescans instead (spec §5.2).
    public var path: String
    /// Security-scoped bookmark for sandbox access across relaunches.
    public var bookmark: Data?
    /// Whether scans of this folder include subfolders (U2; fixes C1).
    public var recursive: Bool
    public var dateAdded: Date

    public init(
        id: Int64? = nil,
        path: String,
        bookmark: Data? = nil,
        recursive: Bool = true,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.recursive = recursive
        self.dateAdded = dateAdded
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct ImportBatchRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "importBatch"

    public var id: Int64?
    public var date: Date

    public init(id: Int64? = nil, date: Date = Date()) {
        self.id = id
        self.date = date
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
