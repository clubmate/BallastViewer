import Foundation
import GRDB

public struct SmartGroupRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "smartGroup"

    public var id: Int64?
    public var name: String
    public var sortOrder: Int

    public init(id: Int64? = nil, name: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct SmartCollectionRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "smartCollection"

    public var id: Int64?
    public var groupId: Int64
    public var name: String
    /// true = AND, false = OR (spec §3.6).
    public var matchAll: Bool
    public var sortOrder: Int

    public init(id: Int64? = nil, groupId: Int64, name: String, matchAll: Bool = true, sortOrder: Int) {
        self.id = id
        self.groupId = groupId
        self.name = name
        self.matchAll = matchAll
        self.sortOrder = sortOrder
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Rule type/operation are stored as plain strings so a library written by a newer
/// app version still opens — the query engine skips what it does not recognise (fixes D6).
public struct CollectionRuleRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "collectionRule"

    public var id: Int64?
    public var collectionId: Int64
    public var type: String
    public var operation: String
    public var value: String
    public var sortOrder: Int

    public init(id: Int64? = nil, collectionId: Int64, type: String, operation: String, value: String, sortOrder: Int) {
        self.id = id
        self.collectionId = collectionId
        self.type = type
        self.operation = operation
        self.value = value
        self.sortOrder = sortOrder
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
