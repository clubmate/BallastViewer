import Foundation
import GRDB

public struct PhotoRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "photo"

    public var id: Int64?
    public var folderId: Int64
    /// Absolute POSIX path — the deduplication key (spec §5.4).
    public var path: String
    /// Last path component, stored so filename sort/rules never re-split paths.
    public var filename: String
    /// 0…5, enforced by a CHECK constraint (fixes D5 at the storage layer).
    public var rating: Int
    /// EXIF orientation. The app produces 1/6/3/8; mirrored values read from files are kept.
    public var orientation: Int
    /// EXIF DateTimeOriginal (improvement U9); nil when the file carries none.
    public var captureDate: Date?
    public var dateAdded: Date
    public var importBatchId: Int64?

    public init(
        id: Int64? = nil,
        folderId: Int64,
        path: String,
        rating: Int = 0,
        orientation: Int = 1,
        captureDate: Date? = nil,
        dateAdded: Date = Date(),
        importBatchId: Int64? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.path = path
        self.filename = URL(fileURLWithPath: path).lastPathComponent
        self.rating = rating
        self.orientation = orientation
        self.captureDate = captureDate
        self.dateAdded = dateAdded
        self.importBatchId = importBatchId
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
