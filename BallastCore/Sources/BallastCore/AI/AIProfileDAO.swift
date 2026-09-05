import Foundation
import GRDB

/// U49: persistence of auto-tagging profiles. A profile is saved WHOLE: the
/// profile row is upserted, its questions and answers are replaced. Nothing
/// else references question or answer ids (suggestions and rejections key on
/// keyword ids), so fresh ids on every save cost nothing and keep the editor
/// trivial — it edits a value, then saves the value.
///
/// U50: questions form a tree (a follow-up question hangs off one answer,
/// `aiQuestion.parentAnswerId`); rows are stored flat and rebuilt here.
public enum AIProfileDAO {
    public static func fetchAll(_ db: Database) throws -> [AIProfile] {
        let profiles = try AIProfileRecord.order(Column("position"), Column("id")).fetchAll(db)
        let questions = try AIQuestionRecord.order(Column("profileId"), Column("position"), Column("id")).fetchAll(db)
        let answers = try AIAnswerRecord.order(Column("questionId"), Column("position"), Column("id")).fetchAll(db)
        let answersByQuestion = Dictionary(grouping: answers, by: \.questionId)
        // Top-level questions group under their profile, follow-ups under
        // their parent answer (a follow-up's profileId is still set — the
        // profile cascade needs it — but it is not a top-level row).
        let topLevelByProfile = Dictionary(grouping: questions.filter { $0.parentAnswerId == nil }, by: \.profileId)
        let followUpsByAnswer = Dictionary(grouping: questions.filter { $0.parentAnswerId != nil }, by: { $0.parentAnswerId! })
        func build(_ question: AIQuestionRecord, depth: Int) -> AIQuestion {
            AIQuestion(
                record: question,
                answers: (answersByQuestion[question.id ?? -1] ?? []).map { answer in
                    AIAnswer(
                        record: answer,
                        // A cycle is impossible (ids only point backwards), the
                        // depth guard just keeps a corrupt row from recursing.
                        followUps: depth < 16
                            ? (followUpsByAnswer[answer.id ?? -1] ?? []).map { build($0, depth: depth + 1) }
                            : []
                    )
                }
            )
        }
        return profiles.map { profile in
            AIProfile(
                record: profile,
                questions: (topLevelByProfile[profile.id ?? -1] ?? []).map { build($0, depth: 0) }
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
        func insert(_ question: AIQuestion, position: Int, parentAnswerId: Int64?) throws -> AIQuestion {
            var qRecord = AIQuestionRecord(
                profileId: profileId, parentAnswerId: parentAnswerId, position: position,
                text: question.text, kind: question.kind, parentKeywordId: question.parentKeywordId
            )
            try qRecord.insert(db)
            var answers: [AIAnswer] = []
            for (aIndex, answer) in question.answers.enumerated() {
                var aRecord = AIAnswerRecord(
                    questionId: qRecord.id!, position: aIndex, value: answer.value,
                    keywordId: answer.keywordId, stopsProfile: answer.stopsProfile
                )
                try aRecord.insert(db)
                var followUps: [AIQuestion] = []
                for (fIndex, followUp) in answer.followUps.enumerated() {
                    followUps.append(try insert(followUp, position: fIndex, parentAnswerId: aRecord.id!))
                }
                answers.append(AIAnswer(record: aRecord, followUps: followUps))
            }
            return AIQuestion(record: qRecord, answers: answers)
        }
        var questions: [AIQuestion] = []
        for (qIndex, question) in profile.questions.enumerated() {
            questions.append(try insert(question, position: qIndex, parentAnswerId: nil))
        }
        return AIProfile(record: record, questions: questions)
    }

    public static func delete(_ profileId: Int64, in db: Database) throws {
        try AIProfileRecord.deleteOne(db, key: profileId)
    }

    public static func setEnabled(_ enabled: Bool, profileId: Int64, in db: Database) throws {
        try AIProfileRecord.filter(key: profileId).updateAll(db, Column("enabled").set(to: enabled))
    }

    /// Keyword ids any profile references — as an answer's keyword or as
    /// the parent of an open question's keywords. Such a keyword is never
    /// garbage-collected (U50).
    public static func referencedKeywordIds(_ db: Database) throws -> Set<Int64> {
        var ids = Set(try Int64.fetchAll(db, sql: "SELECT keywordId FROM aiAnswer WHERE keywordId IS NOT NULL"))
        ids.formUnion(try Int64.fetchAll(db, sql: "SELECT parentKeywordId FROM aiQuestion WHERE parentKeywordId IS NOT NULL"))
        return ids
    }
}
