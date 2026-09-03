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

/// One question of a profile. The model must pick exactly one of the
/// question's answers; `position` is both the order shown and the JSON key
/// ("q1", "q2", …) the model answers under.
public struct AIQuestionRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "aiQuestion"

    public var id: Int64?
    public var profileId: Int64
    public var position: Int
    public var text: String

    public init(id: Int64? = nil, profileId: Int64, position: Int = 0, text: String) {
        self.id = id
        self.profileId = profileId
        self.position = position
        self.text = text
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// One allowed answer to a question, optionally mapped to a keyword. A
/// keyword-less answer ("none", "unsure") is how a question can decline —
/// the model MUST pick something, so every question needs an exit that
/// assigns nothing. `keywordId` goes NULL when the keyword is deleted (FK).
public struct AIAnswerRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "aiAnswer"

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

/// A question with its answers, in order — the in-memory shape the prompt
/// builder, the parser and the editor work on.
public struct AIQuestion: Hashable, Sendable {
    public var record: AIQuestionRecord
    public var answers: [AIAnswerRecord]

    public init(record: AIQuestionRecord, answers: [AIAnswerRecord]) {
        self.record = record
        self.answers = answers
    }

    public var id: Int64? { record.id }
    public var text: String {
        get { record.text }
        set { record.text = newValue }
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

    /// Every keyword any answer of this profile can assign.
    public var keywordIds: Set<Int64> {
        Set(questions.flatMap { $0.answers.compactMap(\.keywordId) })
    }

    /// The default guidance a new profile starts with.
    public static let defaultInstructions =
        "Judge by the main subject of the photo. Ignore people who are small, blurry or clearly in the background."

    /// The starter questionnaire offered on an empty AI tab (keywords left
    /// unmapped — the user connects answers to their own keyword tree).
    public static func starter() -> AIProfile {
        func question(_ text: String, _ values: [String], stop: String? = nil) -> AIQuestion {
            AIQuestion(
                record: AIQuestionRecord(profileId: 0, text: text),
                answers: values.map { AIAnswerRecord(questionId: 0, value: $0, stopsProfile: $0 == stop) }
            )
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
