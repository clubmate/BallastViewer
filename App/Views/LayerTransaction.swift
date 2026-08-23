import QuartzCore

extension CATransaction {
    /// Runs layer mutations with implicit animations disabled — image swaps,
    /// transforms and selection borders must land in the same frame, never
    /// cross-fade (Q5: rotation is instant).
    static func withoutAnimation(_ changes: () -> Void) {
        begin()
        setDisableActions(true)
        changes()
        commit()
    }
}
