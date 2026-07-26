/// The state broadcast that drives control-surface LED feedback (spec §13.6):
/// the anchor photo's resolved keyword paths and rating, plus the view mode —
/// or ([], 0) when there is no anchor. Recomputed whenever the anchor, the
/// photo list, or the view mode changes. Step 11's LED computer consumes this;
/// publishing it now keeps the culling pipeline honest about its triggers.
public struct ControlSurfaceState: Equatable, Sendable {
    /// Resolved uppercase paths ("PEOPLE > ANNA") of the anchor's keywords.
    public var anchorKeywords: Set<String>
    public var anchorRating: Int
    public var isSingleView: Bool

    public init(
        anchorKeywords: Set<String> = [],
        anchorRating: Int = 0,
        isSingleView: Bool = false
    ) {
        self.anchorKeywords = anchorKeywords
        self.anchorRating = anchorRating
        self.isSingleView = isSingleView
    }
}
