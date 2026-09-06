import Foundation
import GRDB
import Testing
@testable import BallastCore

/// U55: a MULTIPLE question — the model picks every answer that applies,
/// answered as a JSON list; the parser is lenient on the shape and drops the
/// exits when a real answer sits beside them.
@Suite struct AIMultipleChoiceTests {
    /// Scene elements (multiple, "none" exit) → follow-up under "water";
    /// a one-of question after it.
    private func sceneProfile(sky: Int64? = nil, water: Int64? = nil, boat: Int64? = nil) -> AIProfile {
        let boatQuestion = AIQuestion(text: "Is there a boat on the water?", answers: [
            AIAnswer(value: "yes", keywordId: boat),
            AIAnswer(value: "no"),
        ])
        let scene = AIQuestion(text: "Which of these are clearly visible?", kind: .multiple, answers: [
            AIAnswer(value: "sky", keywordId: sky),
            AIAnswer(value: "water", keywordId: water, followUps: [boatQuestion]),
            AIAnswer(value: "trees"),
            AIAnswer(value: "empty frame", stopsProfile: true),
            AIAnswer(value: AIAnswerRecord.noneValue),
        ])
        let light = AIQuestion(text: "What is the lighting?", answers: [
            AIAnswer(value: "sunny"),
            AIAnswer(value: "cloudy"),
        ])
        return AIProfile(record: AIProfileRecord(name: "Scene", instructions: ""), questions: [scene, light])
    }

    private func saved() throws -> (AIProfile, sky: Int64, water: Int64, boat: Int64, db: DatabaseQueue) {
        let dbQueue = try makeTestDatabase()
        return try dbQueue.write { db in
            let sky = try KeywordDAO.ensurePath(["SCENE", "SKY"], groupId: nil, in: db)
            let water = try KeywordDAO.ensurePath(["SCENE", "WATER"], groupId: nil, in: db)
            let boat = try KeywordDAO.ensurePath(["BOAT"], groupId: nil, in: db)
            let profile = try AIProfileDAO.save(sceneProfile(sky: sky, water: water, boat: boat), in: db)
            return (profile, sky, water, boat, dbQueue)
        }
    }

    @Test func multipleKindRoundTripsAndChangesTheHash() throws {
        let (profile, _, _, _, dbQueue) = try saved()
        let loaded = try dbQueue.read { try AIProfileDAO.fetchAll($0) }
        #expect(loaded.first?.questions[0].kind == .multiple)
        #expect(loaded.first?.questions[0].answers.count == 5)
        #expect(AIQuestionKind.multiple.hasAnswerRows)
        #expect(!AIQuestionKind.open.hasAnswerRows)
        var single = profile
        single.questions[0].kind = .choice
        #expect(VLMPrompt.questionnaireHash(for: single) != VLMPrompt.questionnaireHash(for: profile))
    }

    @Test func promptAsksForAListOnlyWhereTheQuestionIsMultiple() throws {
        let (profile, _, _, _, _) = try saved()
        let prompt = VLMPrompt.userPrompt(for: profile)
        #expect(prompt.contains("a question that asks for every answer that applies takes a list"))
        #expect(prompt.contains("1. \"q1\": Which of these are clearly visible? Every answer that applies, as a list, from: \"sky\", \"water\", \"trees\", \"empty frame\", \"none\" (\"none\" alone if nothing applies)"))
        #expect(prompt.contains("2. \"q2\": Only if q1 is \"water\": Is there a boat on the water? One of: \"yes\", \"no\", or \"n/a\" unless q1 is \"water\""))
        #expect(prompt.hasSuffix("a list where the shape shows one: {\"q1\": [\"sky|water|trees|empty frame|none\"], \"q2\": \"yes|no|n/a\", \"q3\": \"sunny|cloudy\"}"))
        // Without a multiple question the wording (and so the cache) is unchanged.
        var single = profile
        single.questions[0].kind = .choice
        let plain = VLMPrompt.userPrompt(for: single)
        #expect(!plain.contains("takes a list"))
        #expect(plain.hasSuffix("Return exactly this shape, one value per key: {\"q1\": \"sky|water|trees|empty frame|none\", \"q2\": \"yes|no|n/a\", \"q3\": \"sunny|cloudy\"}"))
    }

    @Test func parserTakesListsAndStringsAndGatesFollowUpsOnMembership() throws {
        let (profile, sky, water, boat, _) = try saved()
        let ids = profile.flattened.map { $0.question.id! }
        let scene = ids[0], boatQ = ids[1], light = ids[2]

        let list = VLMAnswerParser.parse(#"{"q1": ["sky", "Water"], "q2": "yes", "q3": "sunny"}"#, profile: profile)
        #expect(list[scene]?.value == "sky, water")
        #expect(list[scene]?.chosen.count == 2)
        #expect(list[scene]?.keywordId == nil)     // more than one chosen — use keywordIds
        #expect(list[scene]?.keywordIds == [sky, water])
        #expect(list[boatQ]?.value == "yes")
        #expect(list[light]?.value == "sunny")
        #expect(VLMAnswerParser.keywordIds(in: list) == [sky, water, boat])

        // A comma-separated string works too; duplicates and n/a vanish; order is the question's.
        let string = VLMAnswerParser.parse(#"{"q1": "trees, sky, sky, n/a", "q2": "n/a", "q3": "cloudy"}"#, profile: profile)
        #expect(string[scene]?.value == "sky, trees")
        #expect(string[boatQ] == nil)               // gate "water" not chosen
        #expect(VLMAnswerParser.keywordIds(in: string) == [sky])

        // The follow-up is dropped when its gate is missing from the list, whatever the model said.
        let ungated = VLMAnswerParser.parse(#"{"q1": ["sky"], "q2": "yes", "q3": "sunny"}"#, profile: profile)
        #expect(ungated[boatQ] == nil)
        #expect(VLMAnswerParser.keywordIds(in: ungated) == [sky])

        // "none" beside a real answer is ignored; alone it is the answer (no keyword).
        let mixed = VLMAnswerParser.parse(#"{"q1": ["none", "water"], "q2": "no", "q3": "sunny"}"#, profile: profile)
        #expect(mixed[scene]?.value == "water")
        let none = VLMAnswerParser.parse(#"{"q1": ["none"], "q2": "n/a", "q3": "sunny"}"#, profile: profile)
        #expect(none[scene]?.value == "none")
        #expect(none[scene]?.chosen.count == 1)
        #expect(VLMAnswerParser.keywordIds(in: none).isEmpty)
        #expect(none[light]?.value == "sunny")

        // An ending answer alone ends the questionnaire; beside a real answer it is dropped.
        let ended = VLMAnswerParser.parse(#"{"q1": ["empty frame"], "q2": "n/a", "q3": "sunny"}"#, profile: profile)
        #expect(ended[scene]?.stopsProfile == true)
        #expect(ended[light] == nil)
        let notEnded = VLMAnswerParser.parse(#"{"q1": ["empty frame", "sky"], "q2": "n/a", "q3": "sunny"}"#, profile: profile)
        #expect(notEnded[scene]?.value == "sky")
        #expect(notEnded[light]?.value == "sunny")

        // A literal copy of the shape, an empty list, off-list values and n/a are no answer.
        let copied = VLMAnswerParser.parse(#"{"q1": ["sky|water|trees|empty frame|none"], "q3": "sunny"}"#, profile: profile)
        #expect(copied[scene] == nil)
        #expect(copied[light]?.value == "sunny")
        #expect(VLMAnswerParser.parse(#"{"q1": "sky|water|trees|empty frame|none", "q3": "sunny"}"#, profile: profile)[scene] == nil)
        #expect(VLMAnswerParser.parse(#"{"q1": [], "q3": "sunny"}"#, profile: profile)[scene] == nil)
        #expect(VLMAnswerParser.parse(#"{"q1": ["mountains"], "q3": "sunny"}"#, profile: profile)[scene] == nil)
        #expect(VLMAnswerParser.parse(#"{"q1": "n/a", "q3": "sunny"}"#, profile: profile)[scene] == nil)

        // A one-of question answered as a one-element list is still that answer.
        let wrapped = VLMAnswerParser.parse(#"{"q1": ["sky"], "q3": ["cloudy"]}"#, profile: profile)
        #expect(wrapped[light]?.value == "cloudy")
        #expect(wrapped[light]?.keywordId == nil)
        #expect(VLMAnswerParser.parse(#"{"q1": ["sky"], "q3": ["cloudy", "sunny"]}"#, profile: profile)[light] == nil)
    }
}
