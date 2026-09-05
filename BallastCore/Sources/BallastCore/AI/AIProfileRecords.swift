import Foundation
import GRDB

/// U49: an auto-tagging PROFILE — one questionnaire the vision-language
/// model answers per photo. Profiles are per library (their answers point at
/// this library's keyword ids), can be switched on and off, and a run asks
/// every enabled profile in one pass per photo.
public struct AIProfileRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "aiProfile"

    public var id: Int64?
    public var name: String
    public var enabled: Bool
    public var position: Int
    /// Free-form guidance prepended to the questions ("judge by the main
    /// subject, ignore people in the background"). Editable per profile
    /// because it is where a photo genre's ground rules live.
    public var instructions: String

    public init(id: Int64? = nil, name: String, enabled: Bool = true, position: Int = 0, instructions: String = "") {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.position = position
        self.instructions = instructions
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// How a question is answered (U50).
public enum AIQuestionKind: String, Codable, Hashable, Sendable, DatabaseValueConvertible {
    /// The model picks exactly one of the question's answers.
    case choice
    /// The model answers in its own words; the words become a keyword
    /// (created on demand, as a pending suggestion like any other).
    case open
}

/// One question of a profile. `position` is the order among its siblings;
/// the JSON key the model answers under ("q1", "q2", …) follows the
/// depth-first order of the whole profile (`AIProfile.flattened`).
///
/// A question either sits at the top level (`parentAnswerId` nil) or is a
/// FOLLOW-UP of one answer of an earlier question (U50): it is asked only
/// when that answer was chosen — "Is she wearing a dress?" hangs off
/// "female". The follow-up rows are deleted with their parent answer.
public struct AIQuestionRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "aiQuestion"

    public var id: Int64?
    public var profileId: Int64
    public var parentAnswerId: Int64?
    public var position: Int
    public var text: String
    public var kind: AIQuestionKind
    /// Open questions: the keyword the model's words are created UNDER
    /// (nil = top level). Its existing children are offered to the model as
    /// the preferred vocabulary. NULL when that keyword is deleted (FK).
    public var parentKeywordId: Int64?

    public init(
        id: Int64? = nil, profileId: Int64, parentAnswerId: Int64? = nil, position: Int = 0,
        text: String, kind: AIQuestionKind = .choice, parentKeywordId: Int64? = nil
    ) {
        self.id = id
        self.profileId = profileId
        self.parentAnswerId = parentAnswerId
        self.position = position
        self.text = text
        self.kind = kind
        self.parentKeywordId = parentKeywordId
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// One allowed answer to a question, optionally mapped to a keyword. A
/// keyword-less answer ("none", "unsure") is how a question can decline —
/// the model MUST pick something, so every question needs an exit that
/// assigns nothing. `keywordId` goes NULL when the keyword is deleted (FK).
/// An open question carries at most the "none" exit as an answer row.
public struct AIAnswerRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "aiAnswer"

    /// The literal of the exit answer the editor's "Allow none" adds.
    public static let noneValue = "none"

    public var id: Int64?
    public var questionId: Int64
    public var position: Int
    /// The literal the model answers with — short, lowercase English.
    public var value: String
    public var keywordId: Int64?
    /// Chosen → the profile's LATER questions assign nothing for this photo.
    /// "How many people? none" makes gender/age/angle moot; without the gate
    /// a small model happily answers "female" for an empty beach.
    public var stopsProfile: Bool

    public init(
        id: Int64? = nil, questionId: Int64, position: Int = 0, value: String,
        keywordId: Int64? = nil, stopsProfile: Bool = false
    ) {
        self.id = id
        self.questionId = questionId
        self.position = position
        self.value = value
        self.keywordId = keywordId
        self.stopsProfile = stopsProfile
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// An answer with the follow-up questions hanging off it (U50) — the
/// in-memory tree node the prompt builder, the parser and the editor share.
public struct AIAnswer: Hashable, Sendable {
    public var record: AIAnswerRecord
    public var followUps: [AIQuestion]

    public init(record: AIAnswerRecord, followUps: [AIQuestion] = []) {
        self.record = record
        self.followUps = followUps
    }

    public init(value: String, keywordId: Int64? = nil, stopsProfile: Bool = false, followUps: [AIQuestion] = []) {
        self.record = AIAnswerRecord(questionId: 0, value: value, keywordId: keywordId, stopsProfile: stopsProfile)
        self.followUps = followUps
    }

    public var id: Int64? { record.id }
    public var value: String {
        get { record.value }
        set { record.value = newValue }
    }
    public var keywordId: Int64? {
        get { record.keywordId }
        set { record.keywordId = newValue }
    }
    public var stopsProfile: Bool {
        get { record.stopsProfile }
        set { record.stopsProfile = newValue }
    }
}

/// A question with its answers (and their follow-ups), in order.
public struct AIQuestion: Hashable, Sendable {
    public var record: AIQuestionRecord
    public var answers: [AIAnswer]

    public init(record: AIQuestionRecord, answers: [AIAnswer]) {
        self.record = record
        self.answers = answers
    }

    public init(text: String, kind: AIQuestionKind = .choice, parentKeywordId: Int64? = nil, answers: [AIAnswer] = []) {
        self.record = AIQuestionRecord(profileId: 0, text: text, kind: kind, parentKeywordId: parentKeywordId)
        self.answers = answers
    }

    public var id: Int64? { record.id }
    public var text: String {
        get { record.text }
        set { record.text = newValue }
    }
    public var kind: AIQuestionKind {
        get { record.kind }
        set { record.kind = newValue }
    }
    public var parentKeywordId: Int64? {
        get { record.parentKeywordId }
        set { record.parentKeywordId = newValue }
    }

    /// The keyword-less "none" exit, if the question has one.
    public var noneAnswer: AIAnswer? {
        answers.first { $0.value == AIAnswerRecord.noneValue && $0.keywordId == nil }
    }

    /// Every question below this one, depth first (follow-ups of follow-ups
    /// included), each with the answer it hangs off.
    var descendants: [(question: AIQuestion, parent: AIAnswerRecord)] {
        answers.flatMap { answer in
            answer.followUps.flatMap { [(question: $0, parent: answer.record)] + $0.descendants }
        }
    }
}

/// A profile with its questions, in order.
public struct AIProfile: Hashable, Sendable {
    public var record: AIProfileRecord
    public var questions: [AIQuestion]

    public init(record: AIProfileRecord, questions: [AIQuestion]) {
        self.record = record
        self.questions = questions
    }

    public var id: Int64? { record.id }
    public var name: String {
        get { record.name }
        set { record.name = newValue }
    }
    public var enabled: Bool {
        get { record.enabled }
        set { record.enabled = newValue }
    }
    public var instructions: String {
        get { record.instructions }
        set { record.instructions = newValue }
    }

    /// One entry per question in PROMPT order (depth first: a follow-up comes
    /// right after the question it depends on), with the answer that gates it.
    public struct FlatQuestion: Hashable, Sendable {
        public var question: AIQuestion
        /// The answer this question is a follow-up of (nil = top level).
        public var parentAnswer: AIAnswerRecord?
        /// Prompt key of the question the parent answer belongs to.
        public var parentKey: String?
    }

    /// The questions as the model sees them — keys "q1", "q2", … in this order.
    public var flattened: [FlatQuestion] {
        var result: [FlatQuestion] = []
        func walk(_ question: AIQuestion, parent: AIAnswerRecord?, parentKey: String?) {
            let key = VLMPrompt.key(forQuestionAt: result.count)
            result.append(FlatQuestion(question: question, parentAnswer: parent, parentKey: parentKey))
            for answer in question.answers {
                for followUp in answer.followUps {
                    walk(followUp, parent: answer.record, parentKey: key)
                }
            }
        }
        for question in questions { walk(question, parent: nil, parentKey: nil) }
        return result
    }

    /// Every question of the profile, depth first.
    public var allQuestions: [AIQuestion] { flattened.map(\.question) }

    /// Every keyword any answer of this profile can assign.
    public var keywordIds: Set<Int64> {
        Set(allQuestions.flatMap { $0.answers.compactMap(\.keywordId) })
    }

    /// Whether the profile can produce keywords that do not exist yet — an
    /// open question is never "fully reviewed" on a photo.
    public var hasOpenQuestions: Bool {
        allQuestions.contains { $0.kind == .open }
    }

    /// The default guidance a new profile starts with.
    public static let defaultInstructions =
        "Judge by the main subject of the photo. Ignore people who are small, blurry or clearly in the background."

    /// The starter questionnaire (keywords left unmapped — the user connects
    /// answers to their own keyword tree). Used by the `BV_TEST_VLM` hook.
    public static func starter() -> AIProfile {
        func question(_ text: String, _ values: [String], stop: String? = nil) -> AIQuestion {
            AIQuestion(text: text, answers: values.map { AIAnswer(value: $0, stopsProfile: $0 == stop) })
        }
        // One axis per question ("face cut off" is a framing fact, not an
        // angle); "none" on the headcount ends the questionnaire.
        return AIProfile(
            record: AIProfileRecord(name: "People", instructions: defaultInstructions),
            questions: [
                question("How many people are the subject of the photo?", ["none", "one", "two", "three", "group"], stop: "none"),
                question("What is the gender of the main person or people?", ["female", "male", "mixed"]),
                question("How old are the main person or people?", ["child", "young", "adult", "senior", "mixed"]),
                question("From which side is the main person photographed?", ["front", "side", "back"]),
                question("Is the face of the main person cut off by the edge of the frame?", ["no", "yes"]),
                question("What is the lighting or weather of the scene?", ["sunny", "cloudy", "shade", "indoor", "night"]),
            ]
        )
    }
}
