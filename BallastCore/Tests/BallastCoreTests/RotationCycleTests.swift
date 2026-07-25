import Testing
@testable import BallastCore

@Suite struct RotationCycleTests {
    @Test(arguments: [(1, 6), (6, 3), (3, 8), (8, 1)])
    func cycleAdvances(from: Int, to: Int) {
        #expect(RotationCycle.next(after: from) == to)
    }

    @Test(arguments: [2, 4, 5, 7, 0, 9, -1])
    func mirroredAndInvalidOrientationsJumpToSix(orientation: Int) {
        #expect(RotationCycle.next(after: orientation) == 6)
    }
}
