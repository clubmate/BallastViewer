import Testing
@testable import BallastCore

@Suite struct SelectionModelTests {
    let order: [Int64] = [10, 20, 30, 40, 50]

    @Test func selectSingleReplacesSelectionAndAnchor() {
        var s = SelectionModel()
        s.selectSingle(20)
        #expect(s.selectedIds == [20] && s.anchorId == 20)
        s.selectSingle(nil)
        #expect(s.isEmpty && s.anchorId == nil)
    }

    @Test func toggleInsertsRemovesAndManagesAnchor() {
        var s = SelectionModel()
        s.selectSingle(20)
        s.toggle(40)
        #expect(s.selectedIds == [20, 40] && s.anchorId == 40)
        // Toggling the anchor out: others stay selected, anchor becomes nil (§10.1).
        s.toggle(40)
        #expect(s.selectedIds == [20] && s.anchorId == nil)
        // Toggling a non-anchor member out keeps the anchor.
        s.toggle(40)
        s.toggle(20)
        #expect(s.selectedIds == [40] && s.anchorId == 40)
    }

    @Test func rangeSelectionSpansAnchorToTargetInclusive() {
        var s = SelectionModel()
        s.selectSingle(20)
        s.selectRange(to: 50, in: order)
        #expect(s.selectedIds == [20, 30, 40, 50] && s.anchorId == 50)
        // Backwards range from the new anchor.
        s.selectRange(to: 10, in: order)
        #expect(s.selectedIds == [10, 20, 30, 40, 50] && s.anchorId == 10)
    }

    @Test func rangeWithoutAnchorDegradesToSingle() {
        var s = SelectionModel()
        s.selectRange(to: 30, in: order)
        #expect(s.selectedIds == [30] && s.anchorId == 30)
    }
}

@Suite struct OrientationTransformTests {
    @Test(arguments: [
        (1, 0, false), (2, 0, true), (3, 180, false), (4, 180, true),
        (5, 90, true), (6, 90, false), (7, 270, true), (8, 270, false),
        (99, 0, false),
    ])
    func exifTable(orientation: Int, degrees: Int, mirrored: Bool) {
        let t = OrientationTransform.forEXIF(orientation)
        #expect(t.rotationDegrees == degrees)
        #expect(t.mirroredHorizontally == mirrored)
    }

    @Test func dimensionSwap() {
        #expect(OrientationTransform.forEXIF(6).swapsDimensions)
        #expect(OrientationTransform.forEXIF(8).swapsDimensions)
        #expect(!OrientationTransform.forEXIF(3).swapsDimensions)
    }
}

@Suite struct ThumbnailBucketsTests {
    @Test func picksSmallestCoveringBucket() {
        #expect(ThumbnailBuckets.bucket(forPixelSize: 100) == 256)
        #expect(ThumbnailBuckets.bucket(forPixelSize: 256) == 256)
        #expect(ThumbnailBuckets.bucket(forPixelSize: 257) == 768)
        #expect(ThumbnailBuckets.bucket(forPixelSize: 2000) == 2048)
        #expect(ThumbnailBuckets.bucket(forPixelSize: 9999) == 2048)
    }
}
