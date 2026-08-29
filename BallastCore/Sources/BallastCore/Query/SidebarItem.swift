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

    public var encoded: String {
        switch self {
        case .allPhotos: "allPhotos"
        case .lastImport: "lastImport"
        case .rating(let stars): "rating:\(stars)"
        case .collection(let id): "collection:\(id)"
        }
    }

    public init?(encoded: String) {
        if encoded == "allPhotos" {
            self = .allPhotos
        } else if encoded == "lastImport" {
            self = .lastImport
        } else if encoded.hasPrefix("rating:"), let stars = Int(encoded.dropFirst(7)),
                  (0...5).contains(stars) {
            self = .rating(stars)
        } else if encoded.hasPrefix("collection:"), let id = Int64(encoded.dropFirst(11)) {
            self = .collection(id)
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
    /// - `collection`: rule evaluation; a deleted/unknown id matches nothing.
    /// - `collection`: compiled rule evaluation; a missing entry means a
    ///   deleted/unknown id → matches nothing.
    ///
    /// Callers compile each collection's rules once (`CompiledRules`) instead
    /// of re-parsing them for every photo.
    public static func matches(
        _ photo: PhotoRecord,
        facts: @autoclosure () -> PhotoQueryFacts,
        item: SidebarItem,
        compiledCollections: [Int64: CompiledRules],
        lastImportBatchId: Int64?
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
        }
    }
}
