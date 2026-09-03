import Foundation

/// U49: a profile as a portable JSON document. Keyword ids are per library,
/// so the export carries keyword PATHS ("PEOPLE > FRAU"); an import resolves
/// them against the target library's tree and leaves unknown paths unmapped
/// (reported, never invented).
public struct AIProfileExport: Codable, Equatable, Sendable {
    public struct Answer: Codable, Equatable, Sendable {
        public var value: String
        public var keywordPath: String?
        public var stopsProfile: Bool

        public init(value: String, keywordPath: String? = nil, stopsProfile: Bool = false) {
            self.value = value
            self.keywordPath = keywordPath
            self.stopsProfile = stopsProfile
        }
    }

    public struct Question: Codable, Equatable, Sendable {
        public var text: String
        public var answers: [Answer]

        public init(text: String, answers: [Answer]) {
            self.text = text
            self.answers = answers
        }
    }

    public static let formatVersion = 1

    public var format: Int
    public var name: String
    public var instructions: String
    public var questions: [Question]

    public init(name: String, instructions: String, questions: [Question]) {
        format = Self.formatVersion
        self.name = name
        self.instructions = instructions
        self.questions = questions
    }

    /// Snapshot of a profile with ids turned into paths.
    public init(profile: AIProfile, tree: KeywordTree) {
        self.init(
            name: profile.name,
            instructions: profile.instructions,
            questions: profile.questions.map { question in
                Question(
                    text: question.text,
                    answers: question.answers.map { answer in
                        Answer(
                            value: answer.value,
                            keywordPath: answer.keywordId.flatMap { tree.node($0) != nil ? tree.path(of: $0) : nil },
                            stopsProfile: answer.stopsProfile
                        )
                    }
                )
            }
        )
    }

    public struct Resolved: Equatable, Sendable {
        public var profile: AIProfile
        /// Keyword paths of the document that do not exist in this library.
        public var unresolvedPaths: [String]
    }

    /// The document as an unsaved profile of `tree`'s library (enabled,
    /// id nil). Paths are matched component-wise like the search field.
    public func resolved(in tree: KeywordTree) -> Resolved {
        var missing: [String] = []
        let questions = self.questions.map { question in
            AIQuestion(
                record: AIQuestionRecord(profileId: 0, text: question.text),
                answers: question.answers.map { answer in
                    var keywordId: Int64?
                    if let path = answer.keywordPath {
                        let components = path.split(separator: ">").map {
                            $0.trimmingCharacters(in: .whitespaces).uppercased()
                        }
                        keywordId = tree.find(pathComponents: components)
                        if keywordId == nil, !missing.contains(path) { missing.append(path) }
                    }
                    return AIAnswerRecord(
                        questionId: 0, value: answer.value, keywordId: keywordId, stopsProfile: answer.stopsProfile
                    )
                }
            )
        }
        return Resolved(
            profile: AIProfile(
                record: AIProfileRecord(name: name, instructions: instructions),
                questions: questions
            ),
            unresolvedPaths: missing
        )
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> AIProfileExport {
        try JSONDecoder().decode(AIProfileExport.self, from: data)
    }
}
