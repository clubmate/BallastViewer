import Foundation
import GRDB
import Testing
@testable import BallastCore

// U48: AI keyword suggestions — tokenizer, vector math, scoring engine, and
// the v8 schema/DAO contract that keeps pending suggestions out of everything
// confirmed-only (XMP write-through, search facts, chips, counts).

@Suite struct CLIPTokenizerTests {
    private static let tokenizer: CLIPTokenizer = { try! CLIPTokenizer() }()

    @Test func encodesTheCanonicalExample() throws {
        // Reference ids from the original CLIP BPE vocabulary.
        let ids = Self.tokenizer.encode(text: "a photo of a cat")
        #expect(ids == [320, 1125, 539, 320, 2368])
    }

    @Test func lowercasesInput() throws {
        // Keywords are stored UPPERCASE; the tokenizer must fold case itself.
        #expect(
            Self.tokenizer.encode(text: "A PHOTO OF A CAT")
                == Self.tokenizer.encode(text: "a photo of a cat")
        )
    }

    @Test func encodeFullWrapsInBosEosAndPads() throws {
        let full = Self.tokenizer.encodeFull(text: "a photo of a cat")
        #expect(full.count == 77)
        #expect(full[0] == 49406)
        #expect(Array(full[1 ... 5]) == [320, 1125, 539, 320, 2368])
        #expect(full[6] == 49407)
        #expect(full[7...].allSatisfy { $0 == 0 })
    }

    @Test func encodeFullTruncatesOverlongText() throws {
        // Apple's original indexed out of bounds past 75 tokens; ours truncates.
        let text = Array(repeating: "cat", count: 200).joined(separator: " ")
        let full = Self.tokenizer.encodeFull(text: text)
        #expect(full.count == 77)
        #expect(full[0] == 49406)
        #expect(full[76] == 49407)
        #expect(Array(full[1 ... 75]).allSatisfy { $0 == 2368 })
    }
}

@Suite struct EmbeddingMathTests {
    @Test func normalizeProducesUnitLengthAndIsIdempotent() {
        let normalized = EmbeddingMath.l2Normalized([3, 4])
        #expect(abs(normalized[0] - 0.6) < 1e-6)
        #expect(abs(normalized[1] - 0.8) < 1e-6)
        let again = EmbeddingMath.l2Normalized(normalized)
        #expect(abs(again[0] - 0.6) < 1e-6)
        #expect(abs(again[1] - 0.8) < 1e-6)
    }

    @Test func zeroVectorSurvivesNormalization() {
        // A degenerate embedding must not become NaN downstream.
        #expect(EmbeddingMath.l2Normalized([0, 0, 0]) == [0, 0, 0])
    }

    @Test func cosineBasics() {
        #expect(abs(EmbeddingMath.cosine([1, 2, 3], [1, 2, 3]) - 1) < 1e-6)
        #expect(abs(EmbeddingMath.cosine([1, 0], [0, 1])) < 1e-6)
        #expect(abs(EmbeddingMath.cosine([1, 0], [-1, 0]) + 1) < 1e-6)
        #expect(EmbeddingMath.cosine([1, 0], [1]) == 0)          // dimension mismatch
        #expect(EmbeddingMath.cosine([0, 0], [1, 0]) == 0)      // zero magnitude
    }
}

@Suite struct SuggestionEngineTests {
    private func specs(_ pairs: [(Int64, [Float])]) -> [KeywordScoringSpec] {
        pairs.map { KeywordScoringSpec(keywordId: $0.0, textEmbedding: $0.1) }
    }

    @Test func thresholdCutsAndSortsDescending() {
        let result = SuggestionEngine.suggestions(
            photoEmbeddings: [1: [1, 0], 2: [0.8, 0.6], 3: [0, 1]],
            specs: specs([(10, [1, 0])]),
            threshold: 0.5
        )
        // photo 1 scores 1.0, photo 2 scores 0.8, photo 3 scores 0.0.
        #expect(result.map(\.pair.photoId) == [1, 2])
        #expect(result[0].score > result[1].score)
    }

    @Test func skipSetSuppressesKnownPairs() {
        let result = SuggestionEngine.suggestions(
            photoEmbeddings: [1: [1, 0], 2: [1, 0]],
            specs: specs([(10, [1, 0])]),
            threshold: 0.5,
            skip: [PhotoKeywordPair(photoId: 1, keywordId: 10)]
        )
        #expect(result.map(\.pair) == [PhotoKeywordPair(photoId: 2, keywordId: 10)])
    }

    @Test func emptyInputsProduceNothing() {
        #expect(SuggestionEngine.suggestions(photoEmbeddings: [:], specs: [], threshold: 0).isEmpty)
        #expect(
            SuggestionEngine.suggestions(
                photoEmbeddings: [1: [1, 0]], specs: [], threshold: 0
            ).isEmpty)
    }

    @Test func prototypeIsTheNormalizedMean() {
        // Stage 4: mean of [1,0] and [0,1] → normalized [0.707, 0.707].
        let prototype = SuggestionEngine.prototype(of: [[1, 0], [0, 1]])
        #expect(prototype != nil)
        #expect(abs(prototype![0] - 0.7071) < 1e-3)
        #expect(abs(prototype![1] - 0.7071) < 1e-3)
        // No examples → no prototype; opposing examples cancel to zero → nil,
        // never NaN.
        #expect(SuggestionEngine.prototype(of: []) == nil)
        #expect(SuggestionEngine.prototype(of: [[1, 0], [-1, 0]]) == nil)
    }

    @Test func prototypeBlendsInWithExampleCount() {
        // Stage 4 contract, pinned now: α = k/(k+n) with k = 8. Eight examples
        // → 50/50 blend of description and prototype similarity.
        let spec = KeywordScoringSpec(
            keywordId: 10,
            textEmbedding: [1, 0],
            prototypeEmbedding: [0, 1],
            exampleCount: 8
        )
        let score = SuggestionEngine.score(photo: [1, 0], spec: spec)
        #expect(abs(score - 0.5) < 1e-6)
        // Without examples the prototype is ignored even if present.
        var textOnly = spec
        textOnly.exampleCount = 0
        #expect(abs(SuggestionEngine.score(photo: [1, 0], spec: textOnly) - 1) < 1e-6)
    }
}

@Suite struct PendingReviewSidebarTests {
    @Test func encodedRoundTripAndDisplayName() {
        let item = SidebarItem.pendingReview
        #expect(SidebarItem(encoded: item.encoded) == item)
        #expect(item.displayName(collections: [], keywordTree: KeywordTree(records: [])) == "REVIEW AUTO-KEYWORDS")
    }

    @Test func filterMatchesOnlyPhotosWithPendings() {
        var photo = PhotoRecord(folderId: 1, path: "/tmp/a.jpg")
        photo.id = 7
        let facts = PhotoQueryFacts(foldedFilename: "a.jpg")
        func matches(_ pending: Set<Int64>) -> Bool {
            SidebarFilter.matches(
                photo, facts: facts, item: .pendingReview,
                compiledCollections: [:], lastImportBatchId: nil,
                pendingPhotoIds: pending
            )
        }
        #expect(matches([7]))
        #expect(!matches([8]))
        #expect(!matches([]))  // empty queue matches nothing, like .keyword
    }
}

@Suite struct AISchemaTests {
    @Test func v7DatabaseMigratesAndReadsBackConfirmed() throws {
        // A pre-U48 library: rows without a status column come back confirmed
        // and stay visible everywhere.
        let dbQueue = try DatabaseQueue()
        try LibrarySchema.migrator.migrate(dbQueue, upTo: "v7-lightroom-merged")
        try dbQueue.write { db in
            try db.execute(sql: "INSERT INTO folder (path, recursive, dateAdded) VALUES ('/tmp/p', 1, ?)", arguments: [Date()])
            try db.execute(sql: "INSERT INTO photo (folderId, path, filename, dateAdded) VALUES (1, '/tmp/p/a.jpg', 'a.jpg', ?)", arguments: [Date()])
            try db.execute(sql: "INSERT INTO keyword (name) VALUES ('HANDY')")
            try db.execute(sql: "INSERT INTO photoKeyword (photoId, keywordId) VALUES (1, 1)")
        }
        try LibrarySchema.migrator.migrate(dbQueue)
        try dbQueue.read { db in
            let record = try PhotoKeywordRecord.fetchOne(db)
            #expect(record?.status == .confirmed)
            let map = try PhotoDAO.fetchKeywordIdsByPhoto(db)
            #expect(map == [1: [1]])
            let keyword = try KeywordRecord.fetchOne(db)
            #expect(keyword?.aiDescription == nil)
        }
    }

    @Test func pendingRowsAreInvisibleToTheSnapshotMap() throws {
        // THE load-bearing filter: everything confirmed-only (write-through,
        // facts, chips) derives from fetchKeywordIdsByPhoto.
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            let photoId = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/a.jpg")
            let confirmedId = try KeywordDAO.ensurePath(["HANDY"], groupId: nil, in: db)
            let pendingId = try KeywordDAO.ensurePath(["BEINE"], groupId: nil, in: db)
            try PhotoDAO.assignKeyword(confirmedId, toPhotoIds: [photoId], in: db)
            try PhotoKeywordRecord(photoId: photoId, keywordId: pendingId, status: .pending).insert(db)
            let map = try PhotoDAO.fetchKeywordIdsByPhoto(db)
            #expect(map == [photoId: [confirmedId]])
        }
    }

    @Test func manualAssignPromotesPendingToConfirmed() throws {
        // Typing a keyword the AI already suggested is an implicit accept —
        // the upsert must flip the row instead of being swallowed by the PK.
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            let photoId = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/a.jpg")
            let keywordId = try KeywordDAO.ensurePath(["HANDY"], groupId: nil, in: db)
            try PhotoKeywordRecord(photoId: photoId, keywordId: keywordId, status: .pending).insert(db)
            try PhotoDAO.assignKeyword(keywordId, toPhotoIds: [photoId], in: db)
            let record = try PhotoKeywordRecord.fetchOne(db)
            #expect(record?.status == .confirmed)
            #expect(try PhotoKeywordRecord.fetchCount(db) == 1)
        }
    }

    @Test func mergePreservesStatusAndRejections() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            let a = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/a.jpg")
            let b = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/b.jpg")
            let c = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/c.jpg")
            let source = try KeywordDAO.ensurePath(["ALT"], groupId: nil, in: db)
            let target = try KeywordDAO.ensurePath(["NEU"], groupId: nil, in: db)
            // a: pending on source only → arrives pending on target.
            try PhotoKeywordRecord(photoId: a, keywordId: source, status: .pending).insert(db)
            // b: confirmed on source, pending on target → target upgraded.
            try PhotoKeywordRecord(photoId: b, keywordId: source, status: .confirmed).insert(db)
            try PhotoKeywordRecord(photoId: b, keywordId: target, status: .pending).insert(db)
            // c: rejection memory on the source survives the merge.
            try RejectedSuggestionRecord(photoId: c, keywordId: source).insert(db)
            try KeywordDAO.merge(source, into: target, in: db)
            let rows = try PhotoKeywordRecord
                .filter(Column("keywordId") == target)
                .fetchAll(db)
            #expect(rows.first { $0.photoId == a }?.status == .pending)
            #expect(rows.first { $0.photoId == b }?.status == .confirmed)
            let rejected = try RejectedSuggestionRecord.fetchAll(db)
            #expect(rejected == [RejectedSuggestionRecord(photoId: c, keywordId: target)])
        }
    }

    @Test func pendingLifecycleRoundTrips() throws {
        // Stage 2: suggest → (accept ⇄ demote) and suggest → reject → restore.
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            let photoId = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/a.jpg")
            let keywordId = try KeywordDAO.ensurePath(["HANDY"], groupId: nil, in: db)
            let pair = PhotoKeywordPair(photoId: photoId, keywordId: keywordId)

            try PhotoDAO.assignPendingKeywords([pair], in: db)
            #expect(try PhotoDAO.fetchPendingKeywordIdsByPhoto(db) == [photoId: [keywordId]])
            #expect(try PhotoDAO.fetchKeywordIdsByPhoto(db).isEmpty)

            try PhotoDAO.confirmPendingKeyword(keywordId, forPhotoIds: [photoId], in: db)
            #expect(try PhotoDAO.fetchPendingKeywordIdsByPhoto(db).isEmpty)
            #expect(try PhotoDAO.fetchKeywordIdsByPhoto(db) == [photoId: [keywordId]])

            try PhotoDAO.demoteKeywordToPending(keywordId, forPhotoIds: [photoId], in: db)
            #expect(try PhotoDAO.fetchPendingKeywordIdsByPhoto(db) == [photoId: [keywordId]])
            #expect(try PhotoDAO.fetchKeywordIdsByPhoto(db).isEmpty)

            try PhotoDAO.deletePendingKeyword(keywordId, forPhotoIds: [photoId], in: db)
            try PhotoDAO.insertRejected(keywordId, forPhotoIds: [photoId], in: db)
            #expect(try PhotoKeywordRecord.fetchCount(db) == 0)
            #expect(try PhotoDAO.fetchRejectedPairs(db) == [pair])

            try PhotoDAO.deleteRejected(keywordId, forPhotoIds: [photoId], in: db)
            #expect(try PhotoDAO.fetchRejectedPairs(db).isEmpty)
        }
    }

    @Test func suggestionRunNeverDemotesConfirmed() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            let photoId = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/a.jpg")
            let keywordId = try KeywordDAO.ensurePath(["HANDY"], groupId: nil, in: db)
            try PhotoDAO.assignKeyword(keywordId, toPhotoIds: [photoId], in: db)
            try PhotoDAO.assignPendingKeywords(
                [PhotoKeywordPair(photoId: photoId, keywordId: keywordId)], in: db
            )
            #expect(try PhotoKeywordRecord.fetchOne(db)?.status == .confirmed)
            // Deletes/demotes of pending never touch a confirmed row either.
            try PhotoDAO.deletePendingKeyword(keywordId, forPhotoIds: [photoId], in: db)
            #expect(try PhotoKeywordRecord.fetchCount(db) == 1)
        }
    }

    @Test func metadataLoadPreservesReviewState() throws {
        // spec §6.4 Load replaces the CONFIRMED set wholesale — but pending
        // suggestions and rejection memory are user-review state, not file
        // state, and survive. A pending keyword present in the file becomes
        // confirmed.
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let folderId = try insertFolder(db)
            let photoId = try insertPhoto(db, folderId: folderId, path: "/tmp/photos/a.jpg")
            let old = try KeywordDAO.ensurePath(["OLD"], groupId: nil, in: db)
            let pendingOnly = try KeywordDAO.ensurePath(["BEINE"], groupId: nil, in: db)
            let pendingInFile = try KeywordDAO.ensurePath(["HANDY"], groupId: nil, in: db)
            let rejected = try KeywordDAO.ensurePath(["FALSCH"], groupId: nil, in: db)
            try PhotoDAO.assignKeyword(old, toPhotoIds: [photoId], in: db)
            try PhotoDAO.assignPendingKeywords(
                [
                    PhotoKeywordPair(photoId: photoId, keywordId: pendingOnly),
                    PhotoKeywordPair(photoId: photoId, keywordId: pendingInFile),
                ], in: db
            )
            try PhotoDAO.insertRejected(rejected, forPhotoIds: [photoId], in: db)

            // The file carries HANDY plus a new keyword; OLD is gone from it.
            let new = try KeywordDAO.ensurePath(["NEU"], groupId: nil, in: db)
            try PhotoDAO.setKeywords([pendingInFile, new], forPhotoId: photoId, in: db)

            #expect(try PhotoDAO.fetchKeywordIdsByPhoto(db) == [photoId: [pendingInFile, new]])
            #expect(try PhotoDAO.fetchPendingKeywordIdsByPhoto(db) == [photoId: [pendingOnly]])
            #expect(try PhotoDAO.fetchRejectedPairs(db)
                == [PhotoKeywordPair(photoId: photoId, keywordId: rejected)])
        }
    }

    @Test func aiDescriptionRoundTripsAndBlankClears() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let id = try KeywordDAO.ensurePath(["HANDY"], groupId: nil, in: db)
            try KeywordDAO.setAIDescription("someone talking on a phone", forKeywordId: id, in: db)
            #expect(try KeywordRecord.fetchOne(db, key: id)?.aiDescription == "someone talking on a phone")
            try KeywordDAO.setAIDescription("   ", forKeywordId: id, in: db)
            #expect(try KeywordRecord.fetchOne(db, key: id)?.aiDescription == nil)
        }
    }

    @Test func treeMirrorsDescriptionChanges() throws {
        let dbQueue = try makeTestDatabase()
        let tree = try dbQueue.write { db in
            try KeywordDAO.ensurePath(["HANDY"], groupId: nil, in: db)
            return KeywordTree(records: try KeywordDAO.fetchAll(db))
        }
        let id = tree.find(pathComponents: ["HANDY"])!
        let updated = tree.settingAIDescription("someone talking on a phone", of: id)
        #expect(updated.node(id)?.aiDescription == "someone talking on a phone")
        #expect(updated.settingAIDescription(nil, of: id).node(id)?.aiDescription == nil)
    }
}
