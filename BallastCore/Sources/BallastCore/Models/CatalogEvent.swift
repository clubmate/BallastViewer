/// Incremental change notification from the in-memory catalog (see CLAUDE.md
/// mutation contract). Views and count stores update from these deltas instead
/// of recomputing everything; `catalogReplaced` is the bulk-change escape hatch
/// (library open/close, import, folder removal).
public enum CatalogEvent: Equatable, Sendable {
    /// The listed photos changed in place (rating, orientation, keywords…).
    case photosUpdated([Int64])
    /// Smart groups, collections or rules changed (create/edit/delete/reorder).
    case collectionsChanged
    /// The whole snapshot was reloaded — rebuild derived state.
    case catalogReplaced
}
