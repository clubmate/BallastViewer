import Foundation
import GRDB

/// One node of the keyword tree. Photos reference keywords by id via `photoKeyword`,
/// so renaming a node is a single UPDATE that propagates everywhere (fixes C4).
///
/// `groupId == nil` means an ad-hoc/free-text keyword: it appears in autocomplete and
/// renders as a grey chip, but is hidden from the vocabulary editor — reproducing the
/// original's vocabulary/index split with one table.
public struct KeywordRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "keyword"

    public var id: Int64?
    public var parentId: Int64?
    public var groupId: Int64?
    /// Single path component, ALWAYS UPPERCASE (invariant enforced by KeywordDAO).
    public var name: String
    /// U48: short English description driving the AI suggestion run. NULL =
    /// this keyword opted out of AI suggestions.
    public var aiDescription: String?

    public init(
        id: Int64? = nil,
        parentId: Int64? = nil,
        groupId: Int64? = nil,
        name: String,
        aiDescription: String? = nil
    ) {
        self.id = id
        self.parentId = parentId
        self.groupId = groupId
        self.name = name
        self.aiDescription = aiDescription
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct KeywordGroupRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "keywordGroup"

    public var id: Int64?
    public var name: String
    /// "#RRGGBB" (or "#RRGGBBAA" — canonical alpha-last order, fixes C8).
    public var color: String
    /// Drag-ordered; determines chip sort priority in the inspector (Q18).
    public var sortOrder: Int

    public init(id: Int64? = nil, name: String, color: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// The six groups seeded into every new library (spec §8.3, exact colours).
    public static let defaults: [(name: String, color: String)] = [
        ("YEAR", "#007AFF"),
        ("META", "#34C759"),
        ("PEOPLE", "#BF5AF2"),
        ("LOCATION", "#FF3B30"),
        ("EVENT", "#AF52DE"),
        ("MISC", "#FF9500"),
    ]
}

/// U48: lifecycle of a keyword assignment. `pending` rows are AI suggestions
/// awaiting review — they never reach the XMP write-through, search, or
/// counts. Rejections live in `rejectedSuggestion`, not here (a tombstone row
/// would occupy the PK and swallow later manual assignments).
public enum PhotoKeywordStatus: String, Codable, Sendable {
    case confirmed
    case pending
}

/// Join row assigning a keyword to a photo.
public struct PhotoKeywordRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "photoKeyword"

    public var photoId: Int64
    public var keywordId: Int64
    public var status: PhotoKeywordStatus

    public init(photoId: Int64, keywordId: Int64, status: PhotoKeywordStatus = .confirmed) {
        self.photoId = photoId
        self.keywordId = keywordId
        self.status = status
    }
}

/// U48: a rejected AI suggestion — remembered so later runs never re-suggest
/// the same (photo, keyword) pair.
public struct RejectedSuggestionRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "rejectedSuggestion"

    public var photoId: Int64
    public var keywordId: Int64

    public init(photoId: Int64, keywordId: Int64) {
        self.photoId = photoId
        self.keywordId = keywordId
    }
}
