import Foundation

/// One (photo, keyword) assignment candidate — the unit the AI run hands to
/// the catalog as a PENDING suggestion, and the key of the rejection memory.
public struct PhotoKeywordPair: Hashable, Sendable {
    public var photoId: Int64
    public var keywordId: Int64

    public init(photoId: Int64, keywordId: Int64) {
        self.photoId = photoId
        self.keywordId = keywordId
    }
}
