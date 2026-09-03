import Foundation
import GRDB
import Testing
@testable import BallastCore

// U48/U49: AI keyword suggestions — the schema/DAO contract that keeps
// pending suggestions out of everything confirmed-only (XMP write-through,
// search facts, chips, counts), plus the U49 profile questionnaire: records,
// prompt building and reply parsing.

@Suite struct PendingReviewSidebarTests {
    @Test func encodedRoundTripAndDisplayName() {
        let item = SidebarItem.pendingReview
        #expect(SidebarItem(encoded: item.encoded) == item)
        #expect(item.displayName(collections: [], keywordTree: KeywordTree(records: [])) == "REVIEW KEYWORDS")
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
}

@Suite struct AIProfileTests {
    private func profile(named name: String = "People") -> AIProfile {
        var starter = AIProfile.starter()
        starter.name = name
        return starter
    }

    @Test func saveAssignsIdsAndRoundTrips() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let frau = try KeywordDAO.ensurePath(["FRAU"], groupId: nil, in: db)
            var draft = profile()
            draft.questions[1].answers[0].keywordId = frau
            let saved = try AIProfileDAO.save(draft, in: db)
            #expect(saved.id != nil)
            #expect(saved.questions.count == 6)
            #expect(saved.questions[0].answers[0].stopsProfile == true)
            #expect(saved.questions[1].answers[0].stopsProfile == false)
            #expect(saved.questions.allSatisfy { $0.id != nil && $0.answers.allSatisfy { $0.id != nil } })
            #expect(saved.questions[1].answers[0].keywordId == frau)
            #expect(saved.keywordIds == [frau])

            let loaded = try AIProfileDAO.fetchAll(db)
            #expect(loaded == [saved])
            // Positions follow array order.
            #expect(loaded[0].questions.map(\.record.position) == [0, 1, 2, 3, 4, 5])
            #expect(loaded[0].questions[0].answers.map(\.value) == ["none", "one", "two", "three", "group"])
        }
    }

    @Test func resaveReplacesQuestionsAndKeepsProfileOrder() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let first = try AIProfileDAO.save(profile(named: "A"), in: db)
            var second = try AIProfileDAO.save(profile(named: "B"), in: db)
            let droppedQuestionId = second.questions[4].id!
            second.questions.removeLast(4)
            second.questions[0].text = "Count the people."
            second.enabled = false
            let resaved = try AIProfileDAO.save(second, in: db)
            #expect(resaved.id == second.id)
            let loaded = try AIProfileDAO.fetchAll(db)
            #expect(loaded.map(\.name) == ["A", "B"])
            #expect(loaded[1].questions.count == 2)
            #expect(loaded[1].questions[0].text == "Count the people.")
            #expect(loaded[1].enabled == false)
            // Orphans of the replaced questionnaire are gone.
            #expect(try AIQuestionRecord.fetchCount(db) == first.questions.count + 2)
            #expect(try AIAnswerRecord.filter(Column("questionId") == droppedQuestionId).fetchCount(db) == 0)
        }
    }

    @Test func deletingProfileCascadesAndDeletingKeywordUnmaps() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let frau = try KeywordDAO.ensurePath(["FRAU"], groupId: nil, in: db)
            var draft = profile()
            draft.questions[1].answers[0].keywordId = frau
            let saved = try AIProfileDAO.save(draft, in: db)
            try KeywordDAO.deleteSubtree(frau, in: db)
            let unmapped = try AIProfileDAO.fetchAll(db)[0]
            #expect(unmapped.questions[1].answers[0].keywordId == nil)
            #expect(unmapped.questions[1].answers[0].value == "female")

            try AIProfileDAO.setEnabled(false, profileId: saved.id!, in: db)
            #expect(try AIProfileDAO.fetchAll(db)[0].enabled == false)

            try AIProfileDAO.delete(saved.id!, in: db)
            #expect(try AIProfileDAO.fetchAll(db).isEmpty)
            #expect(try AIQuestionRecord.fetchCount(db) == 0)
            #expect(try AIAnswerRecord.fetchCount(db) == 0)
        }
    }

    @Test func mergeMovesAnswerMappingsToTheSurvivor() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let alt = try KeywordDAO.ensurePath(["ALT"], groupId: nil, in: db)
            let neu = try KeywordDAO.ensurePath(["NEU"], groupId: nil, in: db)
            var draft = profile()
            draft.questions[0].answers[1].keywordId = alt
            try AIProfileDAO.save(draft, in: db)
            try KeywordDAO.merge(alt, into: neu, in: db)
            #expect(try AIProfileDAO.fetchAll(db)[0].questions[0].answers[1].keywordId == neu)
        }
    }

    @Test func v8LibraryMigratesToProfiles() throws {
        let dbQueue = try DatabaseQueue()
        try LibrarySchema.migrator.migrate(dbQueue, upTo: "v8-ai-suggestions")
        try dbQueue.write { db in
            try db.execute(sql: "INSERT INTO keyword (name, aiDescription) VALUES ('HANDY', 'a phone')")
            try db.execute(sql: "INSERT INTO keyword (name, aiDescription) VALUES ('FRAU', 'a woman')")
            try db.execute(sql: "INSERT INTO keyword (name) VALUES ('OHNE')")
        }
        try LibrarySchema.migrator.migrate(dbQueue)
        try dbQueue.read { db in
            let keyword = try KeywordRecord.fetchOne(db)
            let columns = try db.columns(in: "keyword").map(\.name)
            let profiles = try AIProfileDAO.fetchAll(db)
            #expect(keyword?.name == "HANDY")
            #expect(!columns.contains("aiDescription"))
            // The old prompts survive as a disabled reference profile.
            #expect(profiles.count == 1)
            #expect(profiles[0].enabled == false)
            #expect(profiles[0].questions.isEmpty)
            #expect(profiles[0].instructions.contains("FRAU: a woman"))
            #expect(profiles[0].instructions.contains("HANDY: a phone"))
            #expect(!profiles[0].instructions.contains("OHNE"))
        }
        // A library without any prompt gets no such profile.
        let empty = try DatabaseQueue()
        try LibrarySchema.migrator.migrate(empty, upTo: "v8-ai-suggestions")
        try LibrarySchema.migrator.migrate(empty)
        #expect(try empty.read { try AIProfileDAO.fetchAll($0).isEmpty })
    }

    @Test func exportCarriesPathsAndImportResolvesOrLeavesUnmapped() throws {
        let dbQueue = try makeTestDatabase()
        let (document, tree) = try dbQueue.write { db -> (AIProfileExport, KeywordTree) in
            let frau = try KeywordDAO.ensurePath(["PEOPLE", "FRAU"], groupId: nil, in: db)
            var draft = profile()
            draft.questions[1].answers[0].keywordId = frau
            let saved = try AIProfileDAO.save(draft, in: db)
            let tree = KeywordTree(records: try KeywordDAO.fetchAll(db))
            return (AIProfileExport(profile: saved, tree: tree), tree)
        }
        #expect(document.questions[1].answers[0].keywordPath == "PEOPLE > FRAU")
        #expect(document.questions[0].answers[0].stopsProfile == true)
        let roundTrip = try AIProfileExport.decode(try document.encoded())
        #expect(roundTrip == document)

        // Same library: the path resolves. A foreign path stays unmapped and is reported.
        var foreign = roundTrip
        foreign.questions[1].answers[1].keywordPath = "PEOPLE > MANN"
        let resolved = foreign.resolved(in: tree)
        #expect(resolved.profile.questions[1].answers[0].keywordId == tree.find(pathComponents: ["PEOPLE", "FRAU"]))
        #expect(resolved.profile.questions[1].answers[1].keywordId == nil)
        #expect(resolved.unresolvedPaths == ["PEOPLE > MANN"])
        #expect(resolved.profile.id == nil)
        #expect(resolved.profile.questions[0].answers[0].stopsProfile == true)
    }

    @Test func promptListsQuestionsWithKeysAndValues() {
        var draft = profile()
        draft.instructions = "Judge by the main subject."
        draft.questions = Array(draft.questions.prefix(2))
        let prompt = VLMPrompt.userPrompt(for: draft)
        #expect(prompt.hasPrefix("Judge by the main subject.\n\n"))
        #expect(prompt.contains("1. \"q1\": How many people are the subject of the photo? One of: \"none\", \"one\", \"two\", \"three\", \"group\""))
        #expect(prompt.contains("2. \"q2\": What is the gender of the main person or people? One of: \"female\", \"male\", \"mixed\""))
        #expect(prompt.hasSuffix("Return exactly this shape, one value per key: {\"q1\": \"none|one|two|three|group\", \"q2\": \"female|male|mixed\"}"))
        // Blank instructions leave no leading blank lines.
        draft.instructions = "  "
        #expect(VLMPrompt.userPrompt(for: draft).hasPrefix("Questions"))
    }

    @Test func settingsHashCoversPromptThinkingAndResolution() {
        let base = VLMPrompt.settingsHash(systemPrompt: "a", thinking: false, fullResolution: false)
        #expect(base == VLMPrompt.settingsHash(systemPrompt: "a", thinking: false, fullResolution: false))
        #expect(base != VLMPrompt.settingsHash(systemPrompt: "b", thinking: false, fullResolution: false))
        #expect(base != VLMPrompt.settingsHash(systemPrompt: "a", thinking: true, fullResolution: false))
        #expect(base != VLMPrompt.settingsHash(systemPrompt: "a", thinking: false, fullResolution: true))
    }

    @Test func questionnaireHashIgnoresKeywordMappings() {
        var a = profile()
        var b = profile()
        b.questions[0].answers[0].keywordId = 42
        #expect(VLMPrompt.questionnaireHash(for: a) == VLMPrompt.questionnaireHash(for: b))
        a.questions[0].text += "?"
        #expect(VLMPrompt.questionnaireHash(for: a) != VLMPrompt.questionnaireHash(for: b))
        b.instructions = "other"
        #expect(VLMPrompt.questionnaireHash(for: profile()) != VLMPrompt.questionnaireHash(for: b))
    }

    private func savedProfile() throws -> (AIProfile, Int64, Int64) {
        let dbQueue = try makeTestDatabase()
        return try dbQueue.write { db in
            let frau = try KeywordDAO.ensurePath(["FRAU"], groupId: nil, in: db)
            let einzel = try KeywordDAO.ensurePath(["EINZEL"], groupId: nil, in: db)
            var draft = profile()
            draft.questions[0].answers[1].keywordId = einzel  // "one"
            draft.questions[1].answers[0].keywordId = frau    // "female"
            return (try AIProfileDAO.save(draft, in: db), frau, einzel)
        }
    }

    @Test func stopAnswerEndsTheQuestionnaireAndDigitsMatchNumberWords() throws {
        let (saved, frau, einzel) = try savedProfile()
        // "none" on the headcount stops the profile: the "female" that a small
        // model still emits assigns nothing.
        let stopped = VLMAnswerParser.parse(#"{"q1": "none", "q2": "female", "q3": "adult"}"#, profile: saved)
        #expect(stopped.count == 1)
        #expect(stopped[saved.questions[0].id!]?.value == "none")
        #expect(VLMAnswerParser.keywordIds(in: stopped).isEmpty)
        // A digit for a number word.
        let digit = VLMAnswerParser.parse(#"{"q1": 1, "q2": "female"}"#, profile: saved)
        #expect(digit[saved.questions[0].id!]?.value == "one")
        #expect(VLMAnswerParser.keywordIds(in: digit) == [frau, einzel])
        // A nested trailing object does not hide the real answer object.
        let nested = #"{"q1": "one", "q2": "female", "notes": {"why": "portrait"}}"#
        #expect(VLMAnswerParser.parse(nested, profile: saved)[saved.questions[0].id!]?.value == "one")
    }

    @Test func parserMapsCleanJSONToAnswersAndKeywords() throws {
        let (saved, frau, einzel) = try savedProfile()
        let reply = #"{"q1": "one", "q2": "female", "q3": "adult", "q4": "front", "q5": "no", "q6": "indoor"}"#
        let parsed = VLMAnswerParser.parse(reply, profile: saved)
        #expect(parsed.count == 6)
        #expect(parsed[saved.questions[0].id!]?.value == "one")
        #expect(VLMAnswerParser.keywordIds(in: parsed) == [frau, einzel])
    }

    @Test func parserIsLenientOnWrappingButStrictOnValues() throws {
        let (saved, frau, _) = try savedProfile()
        // Fenced, pretty-printed, odd casing, stray punctuation, one off-list value.
        let reply = """
        Sure! Here is the answer:
        ```json
        {
          "q1": "Group.",
          "q2": "FEMALE",
          "q3": "teenager",
          "q4": "Front-",
          "q5": 7,
          "q6": "In-door"
        }
        ```
        """
        let parsed = VLMAnswerParser.parse(reply, profile: saved)
        #expect(parsed[saved.questions[0].id!]?.value == "group")
        #expect(parsed[saved.questions[1].id!]?.value == "female")
        #expect(parsed[saved.questions[2].id!] == nil)   // "teenager" is not allowed
        #expect(parsed[saved.questions[3].id!]?.value == "front")
        #expect(parsed[saved.questions[4].id!] == nil)   // 7 is neither "no" nor "yes"
        #expect(parsed[saved.questions[5].id!]?.value == "indoor")
        #expect(VLMAnswerParser.keywordIds(in: parsed) == [frau])
        // A thinking model: the trace (with braces of its own) is skipped and
        // the answer after it is read; an unfinished trace yields nothing.
        let thought = """
        <think>Let me look. The photo shows {a group}... I'd say "q1": "group"? No — one person.</think>
        {"q1": "one", "q2": "female"}
        """
        let afterThinking = VLMAnswerParser.parse(thought, profile: saved)
        #expect(afterThinking[saved.questions[0].id!]?.value == "one")
        #expect(afterThinking[saved.questions[1].id!]?.value == "female")
        #expect(VLMAnswerParser.parse("<think>still thinking {\"q1\": \"one\"}", profile: saved).isEmpty)
        // Qwen3.5 opens <think> inside the prompt: the reply starts mid-trace
        // and only closes it. Braces in the trace must not fool the parser.
        let headless = "The user wants {\"q1\": \"group\"}... no, one person.</think>\n{\"q1\": \"one\", \"q2\": \"male\"}"
        #expect(VLMAnswerParser.parse(headless, profile: saved)[saved.questions[0].id!]?.value == "one")
        #expect(VLMAnswerParser.parse(headless, profile: saved)[saved.questions[1].id!]?.value == "male")
        // The shape Qwen3.5-2B actually produced with thinking on (2026-09-03):
        // a drafted JSON inside the trace, then the fenced answer.
        let fenced = "Drafting: ```json {\"q1\": \"two\"} ``` </think>  ```json\n{\"q1\": \"group\", \"q2\": \"male\"}\n```"
        #expect(VLMAnswerParser.parse(fenced, profile: saved)[saved.questions[0].id!]?.value == "group")
        // Garbage → nothing, never a crash.
        #expect(VLMAnswerParser.parse("no json here", profile: saved).isEmpty)
        #expect(VLMAnswerParser.parse("{broken", profile: saved).isEmpty)
        #expect(VLMAnswerParser.parse("", profile: saved).isEmpty)
    }
}
