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

/// Not `Equatable`: it carries compiled rules. Compare `counts` instead.
public struct CollectionCountsStore: Sendable {
    /// What each photo currently counts towards — the memo that makes deltas
    /// possible without knowing the pre-mutation state.
    private struct Membership: Equatable {
        var rating: Int
        var isLastImport: Bool
        var collectionIds: Set<Int64>
    }

    public private(set) var counts = SidebarCounts()
    private var membershipByPhoto: [Int64: Membership] = [:]
    /// The collections' rules, compiled by the last `rebuild` and reused by
    /// every `update` — rule edits always arrive as a rebuild, so a delta
    /// never needs to recompile.
    private var compiled: [(id: Int64, rules: CompiledRules)] = []

    public init() {}

    /// Full recompute — library open, import, folder removal, rule edits.
    /// Rules are compiled ONCE here; the per-photo loop then runs allocation-
    /// and parse-free (the difference between one and many seconds at 50k).
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
        compiled = Self.compile(collections, rulesByCollection)
        var matched: Set<Int64> = []
        for photo in photos {
            // Unsaved photos have no identity to count under — skip them,
            // exactly like `update` does, instead of piling them onto one id.
            guard let photoId = photo.id else { continue }
            let membership = membership(
                of: photo, lastImportBatchId: lastImportBatchId, facts: facts, scratch: &matched
            )
            add(membership, photoId: photoId)
        }
    }

    /// Delta update after in-place photo mutations, against the collections
    /// compiled by the last `rebuild`. Photos must still be part of the
    /// catalog (removals and rule edits go through `rebuild`).
    public mutating func update(
        changedPhotos: [PhotoRecord],
        lastImportBatchId: Int64?,
        facts: (PhotoRecord) -> PhotoQueryFacts
    ) {
        var matched: Set<Int64> = []
        for photo in changedPhotos {
            guard let photoId = photo.id else { continue }
            let new = membership(
                of: photo, lastImportBatchId: lastImportBatchId, facts: facts, scratch: &matched
            )
            if let old = membershipByPhoto[photoId] {
                guard old != new else { continue }
                remove(old)
            }
            add(new, photoId: photoId)
        }
    }

    private static func compile(
        _ collections: [SmartCollectionRecord],
        _ rulesByCollection: [Int64: [CollectionRuleRecord]]
    ) -> [(id: Int64, rules: CompiledRules)] {
        collections.compactMap { collection in
            collection.id.map {
                ($0, CompiledRules(rulesByCollection[$0] ?? [], matchAll: collection.matchAll))
            }
        }
    }

    /// `scratch` is a caller-owned set reused across photos (cleared, capacity
    /// kept) so the per-photo loop does not allocate one set per photo.
    private func membership(
        of photo: PhotoRecord,
        lastImportBatchId: Int64?,
        facts: (PhotoRecord) -> PhotoQueryFacts,
        scratch matched: inout Set<Int64>
    ) -> Membership {
        let photoFacts = facts(photo)
        matched.removeAll(keepingCapacity: true)
        for collection in compiled where collection.rules.matches(photo, facts: photoFacts) {
            matched.insert(collection.id)
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
