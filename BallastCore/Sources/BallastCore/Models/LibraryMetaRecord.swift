import Foundation
import GRDB

/// Single-row table (id is always 1) holding library-level state.
/// Selected collection and collapsed groups live here — per library, not per app
/// (deliberate improvement over the original's global UserDefaults keys).
public struct LibraryMetaRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "libraryMeta"

    public var id: Int64
    /// Stable identity used to key the thumbnail cache directory in Caches.
    public var libraryUUID: String
    public var createdAt: Date
    /// Batch shown by LAST IMPORT. Kept on empty rescans (Q7).
    public var lastImportBatchId: Int64?
    /// Encoded SidebarItem of the restored sidebar selection.
    public var selectedCollection: String?
    /// JSON array of collapsed smart-group ids.
    public var collapsedGroups: String
    /// User-editable display name; nil/empty falls back to the package filename.
    public var name: String?

    public init(
        id: Int64 = 1,
        libraryUUID: String = UUID().uuidString,
        createdAt: Date = Date(),
        lastImportBatchId: Int64? = nil,
        selectedCollection: String? = nil,
        collapsedGroups: String = "[]",
        name: String? = nil
    ) {
        self.id = id
        self.libraryUUID = libraryUUID
        self.createdAt = createdAt
        self.lastImportBatchId = lastImportBatchId
        self.selectedCollection = selectedCollection
        self.collapsedGroups = collapsedGroups
        self.name = name
    }
}
