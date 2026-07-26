import Foundation
import Testing
@testable import BallastCore

@Suite struct SortEngineTests {
    /// Helper: a photo with controllable sort keys.
    func photo(
        _ id: Int64, path: String, added: TimeInterval = 0, captured: TimeInterval? = nil
    ) -> PhotoRecord {
        var record = PhotoRecord(
            folderId: 1,
            path: path,
            captureDate: captured.map { Date(timeIntervalSinceReferenceDate: $0) },
            dateAdded: Date(timeIntervalSinceReferenceDate: added)
        )
        record.id = id
        return record
    }

    @Test func filenameSortsByRealFilenameNotPath() {
        // U9: /b/001.jpg sorts before /a/999.jpg by filename…
        let photos = [
            photo(1, path: "/a/999.jpg"),
            photo(2, path: "/b/001.jpg"),
        ]
        let byFilename = SortEngine.sorted(photos, by: .filename).map(\.id)
        #expect(byFilename == [2, 1])
        // …while Path keeps the original grouped-by-directory behaviour (Q10).
        let byPath = SortEngine.sorted(photos, by: .path).map(\.id)
        #expect(byPath == [1, 2])
    }

    @Test func filenameTiesBreakByPath() {
        let photos = [
            photo(1, path: "/b/dup.jpg"),
            photo(2, path: "/a/dup.jpg"),
        ]
        #expect(SortEngine.sorted(photos, by: .filename).map(\.id) == [2, 1])
    }

    @Test func dateAddedSortsNewestFirst() {
        let photos = [
            photo(1, path: "/a.jpg", added: 100),
            photo(2, path: "/b.jpg", added: 300),
            photo(3, path: "/c.jpg", added: 200),
        ]
        #expect(SortEngine.sorted(photos, by: .dateAdded).map(\.id) == [2, 3, 1])
    }

    @Test func captureDateSortsAscendingWithUndatedLast() {
        let photos = [
            photo(1, path: "/a.jpg", captured: 500),
            photo(2, path: "/b.jpg"),
            photo(3, path: "/c.jpg", captured: 100),
            photo(4, path: "/d.jpg"),
        ]
        #expect(SortEngine.sorted(photos, by: .captureDate).map(\.id) == [3, 1, 2, 4])
    }

    @Test func randomFollowsTheStableOrder() {
        let photos = (1...5).map { photo(Int64($0), path: "/\($0).jpg") }
        let order: [Int64] = [4, 2, 5, 1, 3]
        #expect(SortEngine.sorted(photos, by: .random, randomOrder: order).map(\.id) == order)
    }

    @Test func randomIdsMissingFromTheOrderKeepRelativeOrderAtTheEnd() {
        let photos = (1...5).map { photo(Int64($0), path: "/\($0).jpg") }
        let sorted = SortEngine.sorted(photos, by: .random, randomOrder: [3, 1]).map(\.id)
        #expect(sorted == [3, 1, 2, 4, 5])
    }

    @Test func comparatorIsATotalOrderOverDistinctPaths() {
        let a = photo(1, path: "/x/a.jpg")
        let b = photo(2, path: "/x/b.jpg")
        for option in [SortOption.filename, .path, .captureDate, .dateAdded] {
            let ab = SortEngine.areInIncreasingOrder(a, b, by: option)
            let ba = SortEngine.areInIncreasingOrder(b, a, by: option)
            #expect(ab != ba, "option \(option) must order distinct paths deterministically")
        }
    }
}
