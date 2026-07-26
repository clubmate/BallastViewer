/// Q2 — stable random order (spec §11.2). A persistent list of photo ids that
/// survives filter changes: ids that left the filtered set are dropped, ids
/// that entered are shuffled and appended at the end, everything else keeps
/// its position. Re-rolled only when the user switches *to* Random; never
/// persisted (new on every launch).
public struct StableRandomOrder: Equatable, Sendable {
    public private(set) var order: [Int64] = []

    public init() {}

    /// Full shuffle — call only when switching to Random from another option.
    public mutating func reroll(
        ids: [Int64],
        using rng: inout some RandomNumberGenerator
    ) {
        order = ids.shuffled(using: &rng)
    }

    /// Align with the current filtered set: drop missing ids, append new ones
    /// shuffled at the end, keep surviving positions.
    public mutating func reconcile(
        with ids: Set<Int64>,
        using rng: inout some RandomNumberGenerator
    ) {
        var remaining = ids
        order.removeAll { id in
            remaining.remove(id) == nil
        }
        order.append(contentsOf: remaining.shuffled(using: &rng))
    }
}
