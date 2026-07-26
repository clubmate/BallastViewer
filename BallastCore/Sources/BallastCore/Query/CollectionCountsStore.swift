/// Live sidebar badge counts (spec §7.6) — maintained *incrementally*: a
/// single-photo change costs O(changed photos × collections), never a sweep
/// over the whole catalog (the original recomputed everything on every change,
/// spec §16.5). Bulk changes (import, open) rebuild from scratch.
public struct SidebarCounts: Equatable, Sendable {
    public var allPhotos = 0
    public var lastImport = 0
    /// Index = star value 0…5; the sidebar renders rows 1…5 (Q9 exact match).
    public var ratings = [Int](repeating: 0, count: 6)
    public var collections: [Int64: Int] = [:]

    public init() {}
}

public struct CollectionCountsStore: Equatable, Sendable {
    /// What each photo currently counts towards — the memo that makes deltas
    /// possible without knowing the pre-mutation state.
    private struct Membership: Equatable {
        var rating: Int
        var isLastImport: Bool
        var collectionIds: Set<Int64>
    }

    public private(set) var counts = SidebarCounts()
    private var membershipByPhoto: [Int64: Membership] = [:]

    public init() {}

    /// Full recompute — library open, import, folder removal, rule edits.
    public mutating func rebuild(
        photos: [PhotoRecord],
        collections: [SmartCollectionRecord],
        rulesByCollection: [Int64: [CollectionRuleRecord]],
        lastImportBatchId: Int64?,
        facts: (PhotoRecord) -> PhotoQueryFacts
    ) {
        counts = SidebarCounts()
        membershipByPhoto = [:]
        membershipByPhoto.reserveCapacity(photos.count)
        counts.collections = Dictionary(
            uniqueKeysWithValues: collections.compactMap { $0.id.map { ($0, 0) } }
        )
        for photo in photos {
            let membership = membership(
                of: photo,
                collections: collections,
                rulesByCollection: rulesByCollection,
                lastImportBatchId: lastImportBatchId,
                facts: facts
            )
            add(membership, photoId: photo.id ?? -1)
        }
    }

    /// Delta update after in-place photo mutations. Photos must still be part
    /// of the catalog (removals go through `rebuild`).
    public mutating func update(
        changedPhotos: [PhotoRecord],
        collections: [SmartCollectionRecord],
        rulesByCollection: [Int64: [CollectionRuleRecord]],
        lastImportBatchId: Int64?,
        facts: (PhotoRecord) -> PhotoQueryFacts
    ) {
        for photo in changedPhotos {
            guard let photoId = photo.id else { continue }
            let new = membership(
                of: photo,
                collections: collections,
                rulesByCollection: rulesByCollection,
                lastImportBatchId: lastImportBatchId,
                facts: facts
            )
            if let old = membershipByPhoto[photoId] {
                guard old != new else { continue }
                remove(old)
            }
            add(new, photoId: photoId)
        }
    }

    private func membership(
        of photo: PhotoRecord,
        collections: [SmartCollectionRecord],
        rulesByCollection: [Int64: [CollectionRuleRecord]],
        lastImportBatchId: Int64?,
        facts: (PhotoRecord) -> PhotoQueryFacts
    ) -> Membership {
        let photoFacts = facts(photo)
        var matched: Set<Int64> = []
        for collection in collections {
            guard let collectionId = collection.id else { continue }
            if QueryEngine.matches(
                photo,
                facts: photoFacts,
                rules: rulesByCollection[collectionId] ?? [],
                matchAll: collection.matchAll
            ) {
                matched.insert(collectionId)
            }
        }
        return Membership(
            rating: photo.rating,
            isLastImport: lastImportBatchId != nil && photo.importBatchId == lastImportBatchId,
            collectionIds: matched
        )
    }

    private mutating func add(_ membership: Membership, photoId: Int64) {
        counts.allPhotos += membershipByPhoto[photoId] == nil ? 1 : 0
        if (0...5).contains(membership.rating) {
            counts.ratings[membership.rating] += 1
        }
        if membership.isLastImport { counts.lastImport += 1 }
        for id in membership.collectionIds {
            counts.collections[id, default: 0] += 1
        }
        membershipByPhoto[photoId] = membership
    }

    private mutating func remove(_ membership: Membership) {
        if (0...5).contains(membership.rating) {
            counts.ratings[membership.rating] -= 1
        }
        if membership.isLastImport { counts.lastImport -= 1 }
        for id in membership.collectionIds {
            counts.collections[id, default: 0] -= 1
        }
    }
}
