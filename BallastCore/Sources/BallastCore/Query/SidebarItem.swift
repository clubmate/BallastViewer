/// One selectable sidebar entry (spec §7.5/§9.2): the pseudo-collections plus
/// user Smart Collections by id. Persisted per library in
/// `libraryMeta.selectedCollection` via the string codec — the selected
/// collection survives relaunch while sort/view mode do not (Q24).
public enum SidebarItem: Hashable, Sendable {
    case allPhotos
    case lastImport
    /// Exact star match (Q9): 1…5 stars, or 0 for the UNRATED row (U28).
    case rating(Int)
    case collection(Int64)
    /// Keyword filter from the inspector's keyword tree (U29): photos carrying
    /// this keyword or any descendant. Not a sidebar row — selecting it
    /// deselects every sidebar entry visually.
    case keyword(Int64)
    /// U48 Stage 3: photos with at least one pending AI suggestion — the
    /// review queue. The row appears only while suggestions are waiting.
    case pendingReview

    public var encoded: String {
        switch self {
        case .allPhotos: "allPhotos"
        case .lastImport: "lastImport"
        case .rating(let stars): "rating:\(stars)"
        case .collection(let id): "collection:\(id)"
        case .keyword(let id): "keyword:\(id)"
        case .pendingReview: "pendingReview"
        }
    }

    /// Human-readable name of the filter this item applies, matching the
    /// sidebar's own wording — the single-view footer shows it so the user
    /// always sees WHY photos are hidden (U44). Collections render their
    /// ancestor chain root-first ("TRIPS > 2009"), like keyword paths do.
    public func displayName(
        collections: [SmartCollectionRecord], keywordTree: KeywordTree
    ) -> String {
        switch self {
        case .allPhotos:
            return "ALL PHOTOS"
        case .lastImport:
            return "LAST IMPORT"
        case .rating(0):
            return "UNRATED"
        case .rating(let stars):
            return String(repeating: "★", count: max(1, min(5, stars)))
        case .collection(let id):
            var byId: [Int64: SmartCollectionRecord] = [:]
            for collection in collections {
                guard let collectionId = collection.id else { continue }
                byId[collectionId] = collection
            }
            var names: [String] = []
            var visited: Set<Int64> = []
            var cursor: Int64? = id
            // Cycle guard, like every other parent walk over hand-editable data.
            while let currentId = cursor, visited.insert(currentId).inserted,
                  let collection = byId[currentId] {
                names.append(collection.name)
                cursor = collection.parentId
            }
            return names.isEmpty ? "?" : names.reversed().joined(separator: " > ")
        case .keyword(let id):
            let path = keywordTree.path(of: id)
            return path.isEmpty ? "?" : path
        case .pendingReview:
            return "REVIEW KEYWORDS"
        }
    }

    public init?(encoded: String) {
        if encoded == "allPhotos" {
            self = .allPhotos
        } else if encoded == "lastImport" {
            self = .lastImport
        } else if encoded == "pendingReview" {
            self = .pendingReview
        } else if encoded.hasPrefix("rating:"), let stars = Int(encoded.dropFirst(7)),
                  (0...5).contains(stars) {
            self = .rating(stars)
        } else if encoded.hasPrefix("collection:"), let id = Int64(encoded.dropFirst(11)) {
            self = .collection(id)
        } else if encoded.hasPrefix("keyword:"), let id = Int64(encoded.dropFirst(8)) {
            self = .keyword(id)
        } else {
            return nil
        }
    }
}

/// Membership test for a sidebar item (spec §7.5 semantics).
public enum SidebarFilter {
    /// - `allPhotos`: no filtering.
    /// - `lastImport`: photos of the remembered batch; before any import this
    ///   is a real match-nothing — the list is empty, not full (Q8).
    /// - `rating(n)`: exactly n stars (Q9); n = 0 is the UNRATED row (U28).
    /// - `collection`: compiled rule-chain evaluation (own rules AND every
    ///   ancestor's — U41); a missing entry means a deleted/unknown id →
    ///   matches nothing.
    /// - `keyword`: the photo carries any keyword in `activeKeywordSubtree`
    ///   (the selected keyword plus its descendants, precomputed by the
    ///   caller — U29). An empty set matches nothing.
    /// - `pendingReview`: the photo is in `pendingPhotoIds` (photos with ≥1
    ///   pending AI suggestion, precomputed by the caller — U48). An empty
    ///   set matches nothing.
    ///
    /// Callers compile the chains once (`CompiledRuleChain.chains`) instead
    /// of re-parsing rules for every photo.
    public static func matches(
        _ photo: PhotoRecord,
        facts: @autoclosure () -> PhotoQueryFacts,
        item: SidebarItem,
        compiledCollections: [Int64: CompiledRuleChain],
        lastImportBatchId: Int64?,
        activeKeywordSubtree: Set<Int64> = [],
        pendingPhotoIds: Set<Int64> = []
    ) -> Bool {
        switch item {
        case .allPhotos:
            return true
        case .lastImport:
            guard let batchId = lastImportBatchId else { return false }
            return photo.importBatchId == batchId
        case .rating(let stars):
            return photo.rating == stars
        case .collection(let id):
            guard let compiled = compiledCollections[id] else { return false }
            return compiled.matches(photo, facts: facts())
        case .keyword:
            return !activeKeywordSubtree.isDisjoint(with: facts().keywordIds)
        case .pendingReview:
            return photo.id.map { pendingPhotoIds.contains($0) } ?? false
        }
    }
}
