import Testing
@testable import BallastCore

/// Deterministic RNG so shuffle results are reproducible in tests.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// Q2 — spec §11.2.
@Suite struct StableRandomOrderTests {
    @Test func rerollShufflesTheFullSet() {
        var rng = SeededRNG(seed: 1)
        var order = StableRandomOrder()
        order.reroll(ids: Array(1...100), using: &rng)
        #expect(Set(order.order) == Set(1...100))
        #expect(order.order != Array(1...100))
    }

    @Test func reconcileKeepsSurvivingPositions() {
        var rng = SeededRNG(seed: 2)
        var order = StableRandomOrder()
        order.reroll(ids: Array(1...10), using: &rng)
        let before = order.order

        // Drop 3 and 7 — everyone else keeps their relative position.
        order.reconcile(with: Set(1...10).subtracting([3, 7]), using: &rng)
        #expect(order.order == before.filter { $0 != 3 && $0 != 7 })
    }

    @Test func reconcileAppendsNewIdsShuffledAtTheEnd() {
        var rng = SeededRNG(seed: 3)
        var order = StableRandomOrder()
        order.reroll(ids: Array(1...10), using: &rng)
        let before = order.order

        order.reconcile(with: Set(1...20), using: &rng)
        #expect(Array(order.order.prefix(10)) == before)
        #expect(Set(order.order.suffix(10)) == Set(11...20))
    }

    @Test func reconcileWithUnchangedSetIsANoOp() {
        var rng = SeededRNG(seed: 4)
        var order = StableRandomOrder()
        order.reroll(ids: Array(1...50), using: &rng)
        let before = order.order
        order.reconcile(with: Set(1...50), using: &rng)
        #expect(order.order == before)
    }

    @Test func droppedIdReentersAtTheEndNotItsOldPosition() {
        var rng = SeededRNG(seed: 5)
        var order = StableRandomOrder()
        order.reroll(ids: Array(1...10), using: &rng)

        order.reconcile(with: Set(1...10).subtracting([5]), using: &rng)
        order.reconcile(with: Set(1...10), using: &rng)
        #expect(order.order.last == 5)
    }
}
