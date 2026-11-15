import Foundation
import GRDB
import Testing
@testable import BallastCore

/// U59: a single question can be switched off. It stays in the
/// questionnaire, is not asked (nor are the follow-ups below it), and the
/// questionnaire then prompts, hashes and parses like one that never had
/// it — so cached replies to the complete questionnaire can be cut down.
@Suite struct AIQuestionSwitchTests {
    /// q1 people (none ends) · q2 gender · q3 dress (after female) · q4 light
    private func profile(peopleOn: Bool = true, genderOn: Bool = true, dressOn: Bool = true, lightOn: Bool = true) -> AIProfile {
        let dress = AIQuestion(text: "Is she wearing a dress?", enabled: dressOn, answers: [
            AIAnswer(value: "yes"),
            AIAnswer(value: "no"),
        ])
        let people = AIQuestion(text: "How many people?", enabled: peopleOn, answers: [
            AIAnswer(value: "one"),
            AIAnswer(value: AIAnswerRecord.noneValue, stopsProfile: true),
        ])
        let gender = AIQuestion(text: "Gender of the main person?", enabled: genderOn, answers: [
            AIAnswer(value: "female", followUps: [dress]),
            AIAnswer(value: "male"),
        ])
        let light = AIQuestion(text: "What is the lighting?", enabled: lightOn, answers: [
            AIAnswer(value: "sunny"),
            AIAnswer(value: "indoor"),
        ])
        return AIProfile(record: AIProfileRecord(name: "People", instructions: ""), questions: [people, gender, light])
    }

    private func saved(_ profile: AIProfile) throws -> AIProfile {
        try makeTestDatabase().write { db in try AIProfileDAO.save(profile, in: db) }
    }

    @Test func switchRoundTripsThroughTheDatabase() throws {
        let dbQueue = try makeTestDatabase()
        let stored = try dbQueue.write { db in try AIProfileDAO.save(profile(dressOn: false, lightOn: false), in: db) }
        let fetched = try dbQueue.read { db in try AIProfileDAO.fetchAll(db) }
        #expect(fetched == [stored])
        #expect(fetched[0].allQuestions.map(\.enabled) == [true, true, false, false])
        #expect(fetched[0].hasDisabledQuestions)
        #expect(!profile().hasDisabledQuestions)
    }

    @Test func v10LibraryGainsTheSwitchAndKeepsEveryQuestionOn() throws {
        let old = try DatabaseQueue()
        try LibrarySchema.migrator.migrate(old, upTo: "v10-ai-branching")
        try old.write { db in
            try db.execute(sql: "INSERT INTO aiProfile (name) VALUES ('P')")
            try db.execute(sql: "INSERT INTO aiQuestion (profileId, text) VALUES (1, 'Q?')")
        }
        try LibrarySchema.migrator.migrate(old)
        let fetched = try old.read { db in try AIProfileDAO.fetchAll(db) }
        #expect(fetched[0].questions.map(\.enabled) == [true])
    }

    @Test func activeQuestionnaireLacksSwitchedOffQuestionsAndTheirFollowUps() {
        // A switched-off follow-up goes alone …
        let withoutDress = profile(dressOn: false)
        #expect(withoutDress.activeIndices == [0, 1, 3])
        #expect(withoutDress.active.allQuestions.map(\.text) == ["How many people?", "Gender of the main person?", "What is the lighting?"])
        // … a switched-off question takes its follow-ups with it.
        let withoutGender = profile(genderOn: false)
        #expect(withoutGender.activeIndices == [0, 3])
        #expect(withoutGender.active.allQuestions.map(\.text) == ["How many people?", "What is the lighting?"])
        // Nothing switched off: the questionnaire is asked as it is.
        #expect(profile().active == profile())
        #expect(profile(peopleOn: false, genderOn: false, lightOn: false).active.questions.isEmpty)
    }

    @Test func activeQuestionnairePromptsAndHashesLikeOneWithoutTheQuestion() {
        let pruned = profile(genderOn: false).active
        let never = AIProfile(record: pruned.record, questions: [profile().questions[0], profile().questions[2]])
        #expect(VLMPrompt.userPrompt(for: pruned) == VLMPrompt.userPrompt(for: never))
        #expect(VLMPrompt.questionnaireHash(for: pruned) == VLMPrompt.questionnaireHash(for: never))
        #expect(!VLMPrompt.userPrompt(for: pruned).contains("Gender"))
        #expect(!VLMPrompt.userPrompt(for: pruned).contains("dress"))
        #expect(VLMPrompt.userPrompt(for: pruned).contains("2. \"q2\": What is the lighting?"))
        // The switch itself is not hashed: all on = the hash it always had.
        #expect(VLMPrompt.questionnaireHash(for: profile()) != VLMPrompt.questionnaireHash(for: pruned))
    }

    @Test func cachedReplyToTheCompleteQuestionnaireIsCutDownAndParses() throws {
        let complete = try saved(profile(genderOn: false))
        let reply = #"{"q1": "one", "q2": "female", "q3": "yes", "q4": "indoor"}"#
        let cut = try #require(VLMAnswerParser.restrict(reply, toActiveOf: complete))
        #expect(cut == #"{"q1":"one","q2":"indoor"}"#)
        let parsed = VLMAnswerParser.parse(cut, profile: complete.active)
        #expect(Set(parsed.values.map(\.value)) == ["one", "indoor"])
        #expect(parsed[try #require(complete.questions[2].id)]?.value == "indoor")
        // The gate of a kept follow-up moves with the keys.
        let withoutPeople = try saved(profile(peopleOn: false))
        let shifted = try #require(VLMAnswerParser.restrict(reply, toActiveOf: withoutPeople))
        #expect(shifted == #"{"q1":"female","q2":"yes","q3":"indoor"}"#)
        #expect(VLMAnswerParser.parse(shifted, profile: withoutPeople.active).count == 3)
        // No JSON, nothing to reuse.
        #expect(VLMAnswerParser.restrict("I cannot tell.", toActiveOf: complete) == nil)
    }
}
