import Foundation
import GRDB
import Testing
@testable import BallastCore

/// U57: several questionnaires travel in ONE prompt per photo (keys numbered
/// straight through, gates shifted with them) and the reply is cut back
/// into per-questionnaire replies that parse and cache like before.
@Suite struct AICombinedPromptTests {
    private func people() -> AIProfile {
        let dress = AIQuestion(text: "What is she wearing?", answers: [
            AIAnswer(value: "dress"),
            AIAnswer(value: "other"),
        ])
        let gender = AIQuestion(text: "Gender of the main person?", answers: [
            AIAnswer(value: "female", followUps: [dress]),
            AIAnswer(value: "male"),
            AIAnswer(value: AIAnswerRecord.noneValue, stopsProfile: true),
        ])
        return AIProfile(record: AIProfileRecord(name: "People", instructions: "The photos are from a wedding."), questions: [gender])
    }

    private func scene() -> AIProfile {
        let place = AIQuestion(text: "Where is this?", answers: [
            AIAnswer(value: "indoors"),
            AIAnswer(value: "outdoors"),
        ])
        return AIProfile(record: AIProfileRecord(name: "Scene", instructions: ""), questions: [place])
    }

    private func saved() throws -> (people: AIProfile, scene: AIProfile) {
        let dbQueue = try makeTestDatabase()
        return try dbQueue.write { db in
            (try AIProfileDAO.save(people(), in: db), try AIProfileDAO.save(scene(), in: db))
        }
    }

    @Test func oneQuestionnaireRendersExactlyAsBefore() {
        #expect(VLMPrompt.questions(for: [people()]) == VLMPrompt.userPrompt(for: people()))
        #expect(VLMPrompt.questions(for: [scene()]) == VLMPrompt.userPrompt(for: scene()))
    }

    @Test func questionnairesAreNumberedStraightThroughAndGatesShift() {
        let prompt = VLMPrompt.questions(for: [scene(), people()])
        #expect(prompt.hasPrefix("The photos are from a wedding.\n\nQuestions (answer each with exactly one of its allowed values):\n"))
        #expect(prompt.contains("1. \"q1\": Where is this? One of: \"indoors\", \"outdoors\"\n"))
        #expect(prompt.contains("2. \"q2\": Gender of the main person? One of: \"female\", \"male\", \"none\"\n"))
        #expect(prompt.contains("3. \"q3\": Only if q2 is \"female\": What is she wearing? One of: \"dress\", \"other\", or \"n/a\" unless q2 is \"female\"\n"))
        #expect(prompt.hasSuffix("Return exactly this shape, one value per key: {\"q1\": \"indoors|outdoors\", \"q2\": \"female|male|none\", \"q3\": \"dress|other|n/a\"}"))
        // One header, one shape.
        #expect(prompt.components(separatedBy: "Questions (").count == 2)
        #expect(prompt.components(separatedBy: "Return exactly").count == 2)
        #expect(VLMPrompt.instructions(systemPrompt: "SYS", questions: "Q") == "SYS\n\nQ")
        #expect(VLMPrompt.answerBudget(questionCount: 3) == 256)
        #expect(VLMPrompt.answerBudget(questionCount: 20) == 800)
    }

    @Test func replyIsCutIntoPerQuestionnaireRepliesThatParse() throws {
        let (people, scene) = try saved()
        let counts = [scene.flattened.count, people.flattened.count]
        #expect(counts == [1, 2])
        let reply = "Sure: {\"q1\": \"outdoors\", \"q2\": \"female\", \"q3\": \"dress\"}"
        let parts = try #require(VLMAnswerParser.split(reply, counts: counts))
        #expect(parts == ["{\"q1\":\"outdoors\"}", "{\"q1\":\"female\",\"q2\":\"dress\"}"])
        let sceneAnswers = VLMAnswerParser.parse(parts[0], profile: scene)
        #expect(sceneAnswers.values.map(\.value) == ["outdoors"])
        let peopleAnswers = VLMAnswerParser.parse(parts[1], profile: people)
        #expect(Set(peopleAnswers.values.map(\.value)) == ["female", "dress"])

        // Missing keys stay missing; lists and numbers survive the cut.
        let sparse = try #require(VLMAnswerParser.split("{\"q2\": [\"male\", \"none\"], \"q9\": 1}", counts: counts))
        #expect(sparse == ["{}", "{\"q1\":[\"male\",\"none\"]}"])
        // A thinking trace is stripped; one that never closed is no reply.
        let thought = try #require(VLMAnswerParser.split("<think>hmm {\"q1\": \"x\"}</think>{\"q1\": \"indoors\"}", counts: counts))
        #expect(thought[0] == "{\"q1\":\"indoors\"}")
        #expect(VLMAnswerParser.split("<think>still thinking", counts: counts) == nil)
        #expect(VLMAnswerParser.split("no json here", counts: counts) == nil)
    }
}
