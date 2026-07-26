import Foundation
import Testing
@testable import BallastCore

@Suite struct CollectionCountsStoreTests {
    private func photo(_ id: Int64, rating: Int = 0, batch: Int64? = nil) -> PhotoRecord {
        var record = PhotoRecord(
            folderId: 1, path: "/p/\(id).jpg", rating: rating, importBatchId: batch
        )
        record.id = id
        return record
    }

    private func collection(_ id: Int64, matchAll: Bool = true) -> SmartCollectionRecord {
        var record = SmartCollectionRecord(groupId: 1, name: "C\(id)", matchAll: matchAll, sortOrder: 0)
        record.id = id
        return record
    }

    private func rule(_ collectionId: Int64, _ type: String, _ op: String, _ value: String) -> CollectionRuleRecord {
        CollectionRuleRecord(collectionId: collectionId, type: type, operation: op, value: value, sortOrder: 0)
    }

    @Test func rebuildCountsEverything() {
        var store = CollectionCountsStore()
        let photos = [
            photo(1, rating: 0, batch: 5),
            photo(2, rating: 3, batch: 5),
            photo(3, rating: 3),
        ]
        // "rated" = rating > 0; an empty collection matching everything (Q6).
        let collections = [collection(10), collection(11)]
        let rules: [Int64: [CollectionRuleRecord]] = [10: [rule(10, "rating", "greaterThan", "0")]]
        store.rebuild(
            photos: photos, collections: collections, rulesByCollection: rules,
            lastImportBatchId: 5, facts: { _ in PhotoQueryFacts() }
        )
        #expect(store.counts.allPhotos == 3)
        #expect(store.counts.lastImport == 2)
        #expect(store.counts.ratings[0] == 1 && store.counts.ratings[3] == 2)
        #expect(store.counts.collections[10] == 2)
        #expect(store.counts.collections[11] == 3)
    }

    /// The acceptance-critical path: a rating change adjusts star badges and
    /// collection counts via the delta only.
    @Test func ratingChangeUpdatesCountsIncrementally() {
        var store = CollectionCountsStore()
        var photos = (1...4).map { photo($0, rating: 0) }
        let collections = [collection(10)]
        let rules: [Int64: [CollectionRuleRecord]] = [10: [rule(10, "rating", "equals", "3")]]
        store.rebuild(
            photos: photos, collections: collections, rulesByCollection: rules,
            lastImportBatchId: nil, facts: { _ in PhotoQueryFacts() }
        )
        #expect(store.counts.ratings[0] == 4 && store.counts.collections[10] == 0)

        photos[1].rating = 3
        store.update(
            changedPhotos: [photos[1]], collections: collections, rulesByCollection: rules,
            lastImportBatchId: nil, facts: { _ in PhotoQueryFacts() }
        )
        #expect(store.counts.ratings[0] == 3 && store.counts.ratings[3] == 1)
        #expect(store.counts.collections[10] == 1)
        #expect(store.counts.allPhotos == 4)

        photos[1].rating = 4
        store.update(
            changedPhotos: [photos[1]], collections: collections, rulesByCollection: rules,
            lastImportBatchId: nil, facts: { _ in PhotoQueryFacts() }
        )
        #expect(store.counts.ratings[3] == 0 && store.counts.ratings[4] == 1)
        #expect(store.counts.collections[10] == 0)
        #expect(store.counts.allPhotos == 4)
    }

    @Test func unchangedPhotoIsANoOp() {
        var store = CollectionCountsStore()
        let photos = [photo(1, rating: 2)]
        store.rebuild(
            photos: photos, collections: [], rulesByCollection: [:],
            lastImportBatchId: nil, facts: { _ in PhotoQueryFacts() }
        )
        let before = store.counts
        store.update(
            changedPhotos: photos, collections: [], rulesByCollection: [:],
            lastImportBatchId: nil, facts: { _ in PhotoQueryFacts() }
        )
        #expect(store.counts == before)
    }

    @Test func keywordDrivenCollectionReactsToFactChanges() {
        var store = CollectionCountsStore()
        let subject = photo(1)
        let collections = [collection(10)]
        let rules: [Int64: [CollectionRuleRecord]] = [10: [rule(10, "keyword", "contains", "anna")]]
        store.rebuild(
            photos: [subject], collections: collections, rulesByCollection: rules,
            lastImportBatchId: nil, facts: { _ in PhotoQueryFacts() }
        )
        #expect(store.counts.collections[10] == 0)

        // Step 8 will tag photos; counts must follow the new facts.
        store.update(
            changedPhotos: [subject], collections: collections, rulesByCollection: rules,
            lastImportBatchId: nil,
            facts: { _ in PhotoQueryFacts(keywordPaths: ["PEOPLE > ANNA"], keywordGroupIds: [7]) }
        )
        #expect(store.counts.collections[10] == 1)
    }
}
