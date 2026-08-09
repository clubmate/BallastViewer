/// Incremental change notification from the in-memory catalog (see CLAUDE.md
/// mutation contract). Views and count stores update from these deltas instead
/// of recomputing everything; `catalogReplaced` is the bulk-change escape hatch
/// (library open/close, import, folder removal).
public enum CatalogEvent: Equatable, Sendable {
    /// The listed photos changed in place (rating, orientation, keywords…).
    case photosUpdated([Int64])
    /// Collection MEMBERSHIP may have changed (rules edited, collection
    /// created/deleted) — consumers rebuild counts and refilter.
    case collectionsChanged
    /// Cosmetic collection-list change (rename, drag-reorder, empty group
    /// created): no membership changed, so no counts rebuild and no refilter —
    /// a sidebar drag would otherwise pay a full O(photos × collections)
    /// sweep per row crossing.
    case collectionListChanged
    /// The whole snapshot was reloaded — rebuild derived state.
    case catalogReplaced
}
