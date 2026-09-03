import Foundation
import GRDB

/// U49: persistence of auto-tagging profiles. A profile is saved WHOLE: the
/// profile row is upserted, its questions and answers are replaced. Nothing
/// else references question or answer ids (suggestions and rejections key on
/// keyword ids), so fresh ids on every save cost nothing and keep the editor
/// trivial — it edits a value, then saves the value.
public enum AIProfileDAO {
    public static func fetchAll(_ db: Database) throws -> [AIProfile] {
        let profiles = try AIProfileRecord.order(Column("position"), Column("id")).fetchAll(db)
        let questions = try AIQuestionRecord.order(Column("profileId"), Column("position"), Column("id")).fetchAll(db)
        let answers = try AIAnswerRecord.order(Column("questionId"), Column("position"), Column("id")).fetchAll(db)
        let answersByQuestion = Dictionary(grouping: answers, by: \.questionId)
        let questionsByProfile = Dictionary(grouping: questions, by: \.profileId)
        return profiles.map { profile in
            AIProfile(
                record: profile,
                questions: (questionsByProfile[profile.id ?? -1] ?? []).map { question in
                    AIQuestion(record: question, answers: answersByQuestion[question.id ?? -1] ?? [])
                }
            )
        }
    }

    /// Inserts (id nil) or replaces the profile and returns it with ids
    /// assigned. Positions are normalized to the array order.
    @discardableResult
    public static func save(_ profile: AIProfile, in db: Database) throws -> AIProfile {
        var record = profile.record
        if record.id == nil {
            let last = try Int.fetchOne(db, sql: "SELECT MAX(position) FROM aiProfile") ?? -1
            record.position = last + 1
            try record.insert(db)
        } else {
            try record.update(db)
            try AIQuestionRecord.filter(Column("profileId") == record.id!).deleteAll(db)
        }
        let profileId = record.id!
        var questions: [AIQuestion] = []
        for (qIndex, question) in profile.questions.enumerated() {
            var qRecord = AIQuestionRecord(profileId: profileId, position: qIndex, text: question.text)
            try qRecord.insert(db)
            var answers: [AIAnswerRecord] = []
            for (aIndex, answer) in question.answers.enumerated() {
                var aRecord = AIAnswerRecord(
                    questionId: qRecord.id!, position: aIndex, value: answer.value,
                    keywordId: answer.keywordId, stopsProfile: answer.stopsProfile
                )
                try aRecord.insert(db)
                answers.append(aRecord)
            }
            questions.append(AIQuestion(record: qRecord, answers: answers))
        }
        return AIProfile(record: record, questions: questions)
    }

    public static func delete(_ profileId: Int64, in db: Database) throws {
        try AIProfileRecord.deleteOne(db, key: profileId)
    }

    public static func setEnabled(_ enabled: Bool, profileId: Int64, in db: Database) throws {
        try AIProfileRecord.filter(key: profileId).updateAll(db, Column("enabled").set(to: enabled))
    }
}
