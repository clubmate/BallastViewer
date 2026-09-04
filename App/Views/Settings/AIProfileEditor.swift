import BallastCore
import SwiftUI

/// U49: the sheet that edits one keyword questionnaire (`AIProfile`) — name,
/// instructions, and the questions with their allowed answers, each answer
/// optionally mapped to a keyword. Edits a local draft with stable row
/// identities and hands the whole profile back on Save (the DAO replaces it
/// wholesale). The keyword dropdowns of the answer rows are drawn by
/// `keywordDropdownHost()` above the whole form — see `KeywordPathField`.
struct AIProfileEditor: View {
    @Environment(LibraryController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    let onSave: (AIProfile) -> Void

    @State private var record: AIProfileRecord
    @State private var questions: [Draft.Question]

    enum Draft {
        struct Question: Identifiable {
            let id = UUID()
            var text: String
            var answers: [Answer]
        }
        struct Answer: Identifiable {
            let id = UUID()
            var value: String
            var keywordId: Int64?
            var stopsProfile: Bool
        }
    }

    init(profile: AIProfile, onSave: @escaping (AIProfile) -> Void) {
        self.onSave = onSave
        _record = State(initialValue: profile.record)
        _questions = State(initialValue: profile.questions.map { question in
            Draft.Question(
                text: question.text,
                answers: question.answers.map {
                    Draft.Answer(value: $0.value, keywordId: $0.keywordId, stopsProfile: $0.stopsProfile)
                }
            )
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Questionnaire") {
                    TextField("Name", text: $record.name, prompt: Text("Questionnaire name"))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Instructions (ground rules the model reads before the questions)")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $record.instructions)
                            .font(.body)
                            .frame(minHeight: 48, maxHeight: 90)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                    }
                }
                Section {
                    ForEach($questions) { $question in
                        questionEditor($question)
                    }
                    Button {
                        questions.append(Draft.Question(text: "", answers: [Draft.Answer(value: "", keywordId: nil, stopsProfile: false)]))
                    } label: {
                        Label("Add Question", systemImage: "plus")
                    }
                } header: {
                    Text("Questions")
                } footer: {
                    Text("Ask in ENGLISH. The model must pick exactly one answer per question, so give every question an answer that assigns nothing (“none”, “unsure”) for photos the question does not apply to. Answers are short lowercase words. “Ends” on an answer stops the questionnaire for that photo — “no person” makes gender or age moot.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .keywordDropdownHost()
            Divider()
            HStack {
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(assembled())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
            .padding(12)
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 560, idealHeight: 640)
    }

    private func questionEditor(_ question: Binding<Draft.Question>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("", text: question.text, prompt: Text("Question, e.g. How many people are the subject of the photo?"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                Button {
                    questions.removeAll { $0.id == question.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove question")
            }
            ForEach(question.answers) { $answer in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary)
                    TextField("", text: $answer.value, prompt: Text("answer"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                    KeywordPathField(keywordId: $answer.keywordId)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("Ends", isOn: $answer.stopsProfile)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .help("When chosen, the remaining questions of this questionnaire assign nothing for the photo (e.g. “no person”)")
                    Button {
                        question.wrappedValue.answers.removeAll { $0.id == answer.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove answer")
                }
            }
            Button {
                question.wrappedValue.answers.append(Draft.Answer(value: "", keywordId: nil, stopsProfile: false))
            } label: {
                Label("Add Answer", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(.leading, 22)
        }
        .padding(.vertical, 4)
    }

    /// Why Save is disabled, or nil when the draft is complete.
    private var problem: String? {
        if record.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the questionnaire a name." }
        if questions.isEmpty { return "Add at least one question." }
        for question in questions {
            if question.text.trimmingCharacters(in: .whitespaces).isEmpty { return "Every question needs text." }
            if question.text.contains("\"") { return "Questions cannot contain double quotes." }
            let values = question.answers.map { $0.value.trimmingCharacters(in: .whitespaces).lowercased() }
            if values.count < 2 { return "Every question needs at least two answers." }
            if values.contains("") { return "Every answer needs a value." }
            if values.contains(where: { $0.contains("\"") || $0.contains("|") }) {
                return "Answers cannot contain double quotes or |."
            }
            if Set(values).count != values.count { return "Answers of one question must differ." }
        }
        return nil
    }

    private func assembled() -> AIProfile {
        var trimmed = record
        trimmed.name = record.name.trimmingCharacters(in: .whitespaces)
        trimmed.instructions = record.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIProfile(
            record: trimmed,
            questions: questions.map { question in
                AIQuestion(
                    record: AIQuestionRecord(profileId: record.id ?? 0, text: question.text.trimmingCharacters(in: .whitespaces)),
                    answers: question.answers.map {
                        AIAnswerRecord(
                            questionId: 0,
                            value: $0.value.trimmingCharacters(in: .whitespaces).lowercased(),
                            keywordId: $0.keywordId,
                            stopsProfile: $0.stopsProfile
                        )
                    }
                )
            }
        )
    }
}
