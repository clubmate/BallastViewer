import Foundation
import GRDB
import Testing
@testable import BallastCore

/// U50: follow-up questions (one pass, parser-gated), open questions whose
/// words become keywords, and the housekeeping of coined keywords.
@Suite struct AIBranchingTests {
    /// People → gender → (female) dress? → (yes) colour (open, under COLORS).
    private func treeProfile(colors: Int64? = nil, dress: Int64? = nil, frau: Int64? = nil) -> AIProfile {
        let colour = AIQuestion(text: "What colour is the dress?", kind: .open, parentKeywordId: colors, answers: [AIAnswer(value: "none")])
        let dressQuestion = AIQuestion(text: "Is she wearing a dress?", answers: [
            AIAnswer(value: "yes", keywordId: dress, followUps: [colour]),
            AIAnswer(value: "no"),
        ])
        let gender = AIQuestion(text: "What is the gender of the main person?", answers: [
            AIAnswer(value: "female", keywordId: frau, followUps: [dressQuestion]),
            AIAnswer(value: "male"),
        ])
        let people = AIQuestion(text: "How many people are the subject of the photo?", answers: [
            AIAnswer(value: "none", stopsProfile: true),
            AIAnswer(value: "one"),
            AIAnswer(value: "group"),
        ])
        return AIProfile(record: AIProfileRecord(name: "Tree", instructions: ""), questions: [people, gender])
    }

    private func saved() throws -> (AIProfile, colors: Int64, dress: Int64, frau: Int64, db: DatabaseQueue) {
        let dbQueue = try makeTestDatabase()
        return try dbQueue.write { db in
            let colors = try KeywordDAO.ensurePath(["COLORS"], groupId: nil, in: db)
            _ = try KeywordDAO.ensurePath(["COLORS", "RED"], groupId: nil, in: db)
            let dress = try KeywordDAO.ensurePath(["CLOTHES", "DRESS"], groupId: nil, in: db)
            let frau = try KeywordDAO.ensurePath(["FRAU"], groupId: nil, in: db)
            let profile = try AIProfileDAO.save(treeProfile(colors: colors, dress: dress, frau: frau), in: db)
            return (profile, colors, dress, frau, dbQueue)
        }
    }

    @Test func treeRoundTripsThroughTheDatabase() throws {
        let (profile, colors, dress, _, dbQueue) = try saved()
        #expect(profile.questions.count == 2)
        let gender = profile.questions[1]
        let dressQuestion = gender.answers[0].followUps[0]
        #expect(dressQuestion.record.parentAnswerId == gender.answers[0].id)
        #expect(dressQuestion.record.profileId == profile.id)
        #expect(dressQuestion.answers[0].keywordId == dress)
        let colour = dressQuestion.answers[0].followUps[0]
        #expect(colour.kind == .open)
        #expect(colour.parentKeywordId == colors)
        #expect(colour.noneAnswer != nil)
        // Prompt order is depth first: people, gender, dress, colour.
        #expect(profile.flattened.map { String($0.question.text.prefix(4)) } == ["How ", "What", "Is s", "What"])
        #expect(profile.flattened[2].parentKey == "q2")
        #expect(profile.flattened[2].parentAnswer?.value == "female")
        #expect(profile.flattened[3].parentKey == "q3")
        #expect(profile.keywordIds == [dress, profile.questions[1].answers[0].keywordId!])
        #expect(profile.hasOpenQuestions)

        let loaded = try dbQueue.read { try AIProfileDAO.fetchAll($0) }
        #expect(loaded == [profile])
        // Re-saving with the branch cut drops the follow-ups (cascade + rebuild).
        var cut = profile
        cut.questions[1].answers[0].followUps = []
        let resaved = try dbQueue.write { try AIProfileDAO.save(cut, in: $0) }
        #expect(resaved.flattened.count == 2)
        #expect(try dbQueue.read { try AIQuestionRecord.fetchCount($0) } == 2)
        #expect(!resaved.hasOpenQuestions)
    }

    @Test func v9LibraryGainsBranchingColumns() throws {
        let old = try DatabaseQueue()
        try LibrarySchema.migrator.migrate(old, upTo: "v9-ai-profiles")
        try old.write { db in
            try db.execute(sql: "INSERT INTO aiProfile (name, enabled, position, instructions) VALUES ('P', 1, 0, '')")
            try db.execute(sql: "INSERT INTO aiQuestion (profileId, position, text) VALUES (1, 0, 'Q?')")
            try db.execute(sql: "INSERT INTO aiAnswer (questionId, position, value, stopsProfile) VALUES (1, 0, 'yes', 0)")
            try db.execute(sql: "INSERT INTO keyword (name) VALUES ('OLD')")
        }
        try LibrarySchema.migrator.migrate(old)
        let profiles = try old.read { try AIProfileDAO.fetchAll($0) }
        #expect(profiles.count == 1)
        #expect(profiles[0].questions[0].kind == .choice)
        #expect(profiles[0].questions[0].record.parentAnswerId == nil)
        #expect(profiles[0].questions[0].answers.map(\.value) == ["yes"])
        #expect(try old.read { try KeywordRecord.fetchOne($0, key: 1)?.aiCreated } == false)
    }

    @Test func promptGatesFollowUpsAndDescribesOpenQuestions() throws {
        let (profile, colors, _, _, _) = try saved()
        let prompt = VLMPrompt.userPrompt(for: profile, vocabulary: [colors: ["RED", "BLUE"]])
        #expect(prompt.contains("1. \"q1\": How many people are the subject of the photo? One of: \"none\", \"one\", \"group\""))
        #expect(prompt.contains("2. \"q2\": What is the gender of the main person? One of: \"female\", \"male\""))
        #expect(prompt.contains("3. \"q3\": Only if q2 is \"female\": Is she wearing a dress? One of: \"yes\", \"no\", or \"n/a\" unless q2 is \"female\""))
        #expect(prompt.contains("4. \"q4\": Only if q3 is \"yes\": What colour is the dress? Answer in one or two English words (prefer one of: \"red\", \"blue\"), or \"none\" if that does not apply, or \"n/a\" unless q3 is \"yes\""))
        #expect(prompt.hasSuffix("{\"q1\": \"none|one|group\", \"q2\": \"female|male\", \"q3\": \"yes|no|n/a\", \"q4\": \"<one or two words>|none|n/a\"}"))
        // Without vocabulary the hint is absent, and the hash does not care.
        let bare = VLMPrompt.userPrompt(for: profile)
        #expect(!bare.contains("prefer one of"))
        #expect(VLMPrompt.questionnaireHash(for: profile) == VLMPrompt.questionnaireHash(for: profile))
        var moved = profile
        moved.questions[1].answers[0].followUps[0].answers[0].followUps[0].parentKeywordId = nil
        #expect(VLMPrompt.questionnaireHash(for: moved) == VLMPrompt.questionnaireHash(for: profile))
        // Re-hanging the follow-up under another answer IS a different questionnaire.
        var rehung = profile
        let dressQuestion = rehung.questions[1].answers[0].followUps.removeFirst()
        rehung.questions[1].answers[1].followUps = [dressQuestion]
        #expect(VLMPrompt.questionnaireHash(for: rehung) != VLMPrompt.questionnaireHash(for: profile))
        var opened = profile
        opened.questions[0].kind = .open
        #expect(VLMPrompt.questionnaireHash(for: opened) != VLMPrompt.questionnaireHash(for: profile))
    }

    @Test func parserDropsUngatedFollowUpsAndCoinsOpenAnswers() throws {
        let (profile, colors, dress, frau, _) = try saved()
        let ids = profile.flattened.map { $0.question.id! }
        // The whole branch taken: every answer counts, the colour is coined.
        let full = VLMAnswerParser.parse(#"{"q1": "one", "q2": "female", "q3": "yes", "q4": "Light blue."}"#, profile: profile)
        #expect(full.count == 4)
        #expect(VLMAnswerParser.keywordIds(in: full) == [frau, dress])
        #expect(full[ids[3]]?.value == "Light blue.")
        #expect(full[ids[3]]?.coined == AICoinedKeyword(name: "LIGHT BLUE", parentKeywordId: colors))
        #expect(VLMAnswerParser.coinedKeywords(in: full) == [AICoinedKeyword(name: "LIGHT BLUE", parentKeywordId: colors)])
        // Gate not met: a small model still answers the follow-ups — dropped.
        let male = VLMAnswerParser.parse(#"{"q1": "one", "q2": "male", "q3": "yes", "q4": "red"}"#, profile: profile)
        #expect(male.count == 2)
        #expect(VLMAnswerParser.keywordIds(in: male).isEmpty)
        #expect(VLMAnswerParser.coinedKeywords(in: male).isEmpty)
        // Gate met but the model declined with n/a, or the exit: no coinage.
        let na = VLMAnswerParser.parse(#"{"q1": "one", "q2": "female", "q3": "yes", "q4": "n/a"}"#, profile: profile)
        #expect(na.count == 3)
        let none = VLMAnswerParser.parse(#"{"q1": "one", "q2": "female", "q3": "yes", "q4": "none"}"#, profile: profile)
        #expect(none.count == 4)
        #expect(none[ids[3]]?.coined == nil)
        #expect(none[ids[3]]?.value == "none")
        // The copied placeholder is not a keyword.
        let copied = VLMAnswerParser.parse(#"{"q1": "one", "q2": "female", "q3": "yes", "q4": "<one or two words>"}"#, profile: profile)
        #expect(copied[ids[3]] == nil)
        // A stop answer ends everything after it, branch or not.
        let stopped = VLMAnswerParser.parse(#"{"q1": "none", "q2": "female", "q3": "yes", "q4": "red"}"#, profile: profile)
        #expect(stopped.count == 1)
        // The parent gate is the parent ANSWER, not just any answer of the question.
        let nested = VLMAnswerParser.parse(#"{"q1": "one", "q2": "female", "q3": "no", "q4": "red"}"#, profile: profile)
        #expect(nested.count == 3)
        #expect(nested[ids[3]] == nil)
    }

    @Test func keywordNamesFromWordsAreStrictButForgiving() {
        #expect(VLMAnswerParser.keywordName(from: " red ") == "RED")
        #expect(VLMAnswerParser.keywordName(from: "\"Dark  green\".") == "DARK GREEN")
        #expect(VLMAnswerParser.keywordName(from: "sky_blue") == "SKY BLUE")
        #expect(VLMAnswerParser.keywordName(from: "") == nil)
        #expect(VLMAnswerParser.keywordName(from: "one or two words") == nil)
        #expect(VLMAnswerParser.keywordName(from: "the dress is a lovely shade of blue") == nil)
        #expect(VLMAnswerParser.keywordName(from: "COLORS > RED") == nil)
        #expect(VLMAnswerParser.keywordName(from: "red|blue") == nil)
        #expect(VLMAnswerParser.keywordName(from: "none") == nil)
        #expect(VLMAnswerParser.keywordName(from: String(repeating: "a", count: 41)) == nil)
    }

    @Test func coinedKeywordsAreCollectedOnlyWhenNothingHoldsThem() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            let colors = try KeywordDAO.ensurePath(["COLORS"], groupId: nil, in: db)
            let (blue, created) = try KeywordDAO.ensureChild(named: "blue", parentId: colors, aiCreated: true, in: db)
            #expect(created?.name == "BLUE")
            #expect(created?.aiCreated == true)
            // Same words again → same row, nothing created.
            let (again, none) = try KeywordDAO.ensureChild(named: " Blue ", parentId: colors, aiCreated: true, in: db)
            #expect(again == blue && none == nil)
            // A user keyword is never collected, even when unused.
            let (red, _) = try KeywordDAO.ensureChild(named: "red", parentId: colors, aiCreated: false, in: db)
            #expect(try KeywordDAO.orphanedAIKeywords(among: [red, colors], in: db).isEmpty)
            // A pending assignment holds it…
            var folder = FolderRecord(path: "/p")
            try folder.insert(db)
            var photo = PhotoRecord(folderId: folder.id!, path: "/p/a.jpg")
            try photo.insert(db)
            try PhotoDAO.assignPendingKeywords([PhotoKeywordPair(photoId: photo.id!, keywordId: blue)], in: db)
            #expect(try KeywordDAO.orphanedAIKeywords(among: [blue], in: db).isEmpty)
            // …a questionnaire reference holds it…
            try PhotoDAO.deletePendingKeyword(blue, forPhotoIds: [photo.id!], in: db)
            let profile = try AIProfileDAO.save(
                AIProfile(record: AIProfileRecord(name: "P"), questions: [AIQuestion(text: "Colour?", kind: .open, parentKeywordId: blue)]),
                in: db
            )
            #expect(try KeywordDAO.orphanedAIKeywords(among: [blue], in: db).isEmpty)
            try AIProfileDAO.delete(profile.id!, in: db)
            // …a child holds it; otherwise it is an orphan.
            let (child, _) = try KeywordDAO.ensureChild(named: "navy", parentId: blue, aiCreated: true, in: db)
            #expect(try KeywordDAO.orphanedAIKeywords(among: [blue], in: db).isEmpty)
            #expect(try KeywordDAO.orphanedAIKeywords(among: [child], in: db).map(\.id) == [child])
            try KeywordDAO.deleteSubtree(child, in: db)
            let orphans = try KeywordDAO.orphanedAIKeywords(among: [blue, red, colors, 9999], in: db)
            #expect(orphans.map(\.id) == [blue])
            try KeywordDAO.deleteSubtree(blue, in: db)
            #expect(try KeywordRecord.fetchOne(db, key: blue) == nil)
            // Undo brings it back under the SAME id.
            try KeywordDAO.restore(orphans, in: db)
            #expect(try KeywordRecord.fetchOne(db, key: blue)?.name == "BLUE")
            try KeywordDAO.restore(orphans, in: db)  // idempotent
            #expect(try KeywordRecord.filter(Column("name") == "BLUE").fetchCount(db) == 1)
            // Merge moves an open question's parent to the survivor.
            let (colours, _) = try KeywordDAO.ensureChild(named: "colours", parentId: nil, aiCreated: false, in: db)
            _ = try AIProfileDAO.save(
                AIProfile(record: AIProfileRecord(name: "Q"), questions: [AIQuestion(text: "Colour?", kind: .open, parentKeywordId: colors)]),
                in: db
            )
            try KeywordDAO.merge(colors, into: colours, in: db)
            #expect(try AIProfileDAO.fetchAll(db).last?.questions[0].parentKeywordId == colours)
            #expect(try AIProfileDAO.referencedKeywordIds(db) == [colours])
        }
    }

    @Test func rejectedOpenAnswersAreRememberedByPath() throws {
        let dbQueue = try makeTestDatabase()
        try dbQueue.write { db in
            var folder = FolderRecord(path: "/p")
            try folder.insert(db)
            var a = PhotoRecord(folderId: folder.id!, path: "/p/a.jpg")
            var b = PhotoRecord(folderId: folder.id!, path: "/p/b.jpg")
            try a.insert(db)
            try b.insert(db)
            try PhotoDAO.insertRejectedAIAnswer(path: "COLORS > BLUE", forPhotoIds: [a.id!, b.id!], in: db)
            try PhotoDAO.insertRejectedAIAnswer(path: "COLORS > BLUE", forPhotoIds: [a.id!], in: db)  // OR IGNORE
            try PhotoDAO.insertRejectedAIAnswer(path: "RED", forPhotoIds: [b.id!], in: db)
            #expect(try PhotoDAO.fetchRejectedAIAnswerPaths(db) == [a.id!: ["COLORS > BLUE"], b.id!: ["COLORS > BLUE", "RED"]])
            try PhotoDAO.deleteRejectedAIAnswer(path: "COLORS > BLUE", forPhotoIds: [b.id!], in: db)
            #expect(try PhotoDAO.fetchRejectedAIAnswerPaths(db) == [a.id!: ["COLORS > BLUE"], b.id!: ["RED"]])
            // Photo rows cascade.
            _ = try PhotoRecord.deleteOne(db, key: a.id!)
            #expect(try PhotoDAO.fetchRejectedAIAnswerPaths(db) == [b.id!: ["RED"]])
        }
    }
}
