import Testing
@testable import BallastCore

/// Q1 — spec §10.4. Order of preference after the anchor drops out:
/// nearest surviving after → nearest surviving before → first → nothing.
@Suite struct NeighbourRuleTests {
    let previous: [Int64] = [1, 2, 3, 4, 5]

    @Test func survivingAnchorIsKeptUnchanged() {
        #expect(NeighbourRule.nextAnchor(for: 3, previousOrder: previous, newOrder: [3, 5]) == 3)
    }

    @Test func prefersNearestSurvivorAfterTheRemovedPhoto() {
        // 3 drops out, 4 survives → 4 (never back to the top).
        #expect(NeighbourRule.nextAnchor(for: 3, previousOrder: previous, newOrder: [1, 2, 4, 5]) == 4)
        // 3 and 4 drop out → 5.
        #expect(NeighbourRule.nextAnchor(for: 3, previousOrder: previous, newOrder: [1, 2, 5]) == 5)
    }

    @Test func fallsBackToNearestSurvivorBefore() {
        // Nothing survives after 3 → nearest before, i.e. 2.
        #expect(NeighbourRule.nextAnchor(for: 3, previousOrder: previous, newOrder: [1, 2]) == 2)
        #expect(NeighbourRule.nextAnchor(for: 5, previousOrder: previous, newOrder: [1, 3]) == 3)
    }

    @Test func fallsBackToFirstOfTheNewList() {
        // No previous photo survives, but new photos entered the filter.
        #expect(NeighbourRule.nextAnchor(for: 3, previousOrder: [3], newOrder: [7, 8]) == 7)
        // Anchor unknown to the previous order → first of the new list.
        #expect(NeighbourRule.nextAnchor(for: 99, previousOrder: previous, newOrder: [4, 5]) == 4)
    }

    @Test func emptyNewListYieldsNothing() {
        #expect(NeighbourRule.nextAnchor(for: 3, previousOrder: previous, newOrder: []) == nil)
    }

    @Test func cullingFlowAdvancesThroughTheWholeList() {
        // Rating photos in an "unrated" collection: each removal advances to the
        // next survivor; the last one falls back to its predecessor's side.
        var order = previous
        var anchor: Int64 = 1
        var visited: [Int64] = [anchor]
        while order.count > 1 {
            let newOrder = order.filter { $0 != anchor }
            anchor = NeighbourRule.nextAnchor(for: anchor, previousOrder: order, newOrder: newOrder)!
            visited.append(anchor)
            order = newOrder
        }
        #expect(visited == [1, 2, 3, 4, 5])
    }
}
