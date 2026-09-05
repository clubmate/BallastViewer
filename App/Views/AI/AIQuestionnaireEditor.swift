import BallastCore
import SwiftUI

/// U50: the editor of one keyword questionnaire (`AIProfile`) — name,
/// instructions, and the QUESTION TREE. A question is a card; its answers
/// are rows inside the card; a follow-up question is a card nested inside
/// the answer it hangs off, drawn with a coloured guide line so the branch
/// is visible at a glance ("2.1 · only after female"). Open questions have
/// no answer rows — the model's words become a keyword.
///
/// Edits a local draft with stable row identities and AUTOSAVES it (400 ms
/// after the last change, and when the view goes away) whenever the draft
/// is complete; an incomplete draft shows why it is not saved yet. The DAO
/// replaces the whole profile per save, which is cheap.
struct AIQuestionnaireEditor: View {
    @Environment(LibraryController.self) private var controller

    let profile: AIProfile

    @State private var draft: Draft
    @State private var lastSaved: Draft
    @State private var saveTask: Task<Void, Never>?

    init(profile: AIProfile) {
        self.profile = profile
        let draft = Draft(profile)
        _draft = State(initialValue: draft)
        _lastSaved = State(initialValue: draft)
    }

    // MARK: Draft

    struct Draft: Equatable {
        var name: String
        var instructions: String
        var questions: [Question]

        struct Question: Identifiable, Equatable {
            let id: UUID
            var text: String
            var kind: AIQuestionKind
            var parentKeywordId: Int64?
            var answers: [Answer]
            /// The keyword-less "none" exit — a checkbox, not a row (U50).
            var allowsNone: Bool
            var noneEnds: Bool

            init(text: String = "", kind: AIQuestionKind = .choice, parentKeywordId: Int64? = nil,
                 answers: [Answer] = [], allowsNone: Bool = false, noneEnds: Bool = false) {
                id = UUID()
                self.text = text
                self.kind = kind
                self.parentKeywordId = parentKeywordId
                self.answers = answers
                self.allowsNone = allowsNone
                self.noneEnds = noneEnds
            }

            init(_ question: AIQuestion) {
                id = UUID()
                text = question.text
                kind = question.kind
                parentKeywordId = question.parentKeywordId
                let none = question.noneAnswer
                allowsNone = none != nil
                noneEnds = none?.stopsProfile ?? false
                answers = question.answers
                    .filter { !($0.value == AIAnswerRecord.noneValue && $0.keywordId == nil) }
                    .map(Answer.init)
            }

            /// Every question below this one, depth first.
            var descendants: [Question] {
                answers.flatMap { $0.followUps.flatMap { [$0] + $0.descendants } }
            }
        }

        struct Answer: Identifiable, Equatable {
            let id: UUID
            var value: String
            var keywordId: Int64?
            var stopsProfile: Bool
            var followUps: [Question]

            init(value: String = "", keywordId: Int64? = nil, stopsProfile: Bool = false, followUps: [Question] = []) {
                id = UUID()
                self.value = value
                self.keywordId = keywordId
                self.stopsProfile = stopsProfile
                self.followUps = followUps
            }

            init(_ answer: AIAnswer) {
                id = UUID()
                value = answer.value
                keywordId = answer.keywordId
                stopsProfile = answer.stopsProfile
                followUps = answer.followUps.map(Question.init)
            }
        }

        init(_ profile: AIProfile) {
            name = profile.name
            instructions = profile.instructions
            questions = profile.questions.map(Question.init)
        }

        var allQuestions: [Question] { questions.flatMap { [$0] + $0.descendants } }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    questionsSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .keywordDropdownHost()
            Divider()
            footer
        }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onDisappear { flushSave() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $draft.name, prompt: Text("Questionnaire name"))
                .labelsHidden()
                .font(.title2.weight(.semibold))
                .textFieldStyle(.plain)
            Text("Instructions — the ground rules the model reads before the questions")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $draft.instructions)
                .font(.body)
                .frame(minHeight: 44, maxHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
    }

    private var questionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Questions").font(.headline)
                Spacer()
                Text("Ask in English. Choices: the model picks one answer, each answer can assign a keyword. Open answer: the model's own words become a keyword. ⤵ adds a follow-up question that is asked only after that answer.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: 460, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
            ForEach($draft.questions) { $question in
                let index = draft.questions.firstIndex { $0.id == question.id } ?? 0
                QuestionCard(
                    question: $question, label: "\(index + 1)", gate: nil, depth: 0,
                    onRemove: { draft.questions.removeAll { $0.id == question.id } }
                )
            }
            Button {
                draft.questions.append(Draft.Question(answers: [Draft.Answer(), Draft.Answer()]))
            } label: {
                Label("Add Question", systemImage: "plus")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let problem {
                Label("Not saved yet — \(problem)", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            } else if draft != lastSaved {
                Label("Saving…", systemImage: "ellipsis.circle").font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Saved in the library", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            let questions = draft.allQuestions.count
            let mapped = draft.allQuestions.flatMap(\.answers).filter { $0.keywordId != nil }.count
            let open = draft.allQuestions.filter { $0.kind == .open }.count
            Text("\(questions) question\(questions == 1 ? "" : "s") · \(mapped) answer\(mapped == 1 ? "" : "s") mapped" + (open > 0 ? " · \(open) open" : ""))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Validation & save

    /// Why the draft is not saved, or nil when it is complete.
    private var problem: String? {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { return "give the questionnaire a name." }
        for question in draft.allQuestions {
            if question.text.trimmingCharacters(in: .whitespaces).isEmpty { return "every question needs text." }
            if question.text.contains("\"") { return "questions cannot contain double quotes." }
            guard question.kind == .choice else { continue }
            let values = question.answers.map { $0.value.trimmingCharacters(in: .whitespaces).lowercased() }
            if values.count + (question.allowsNone ? 1 : 0) < 2 { return "every question needs at least two answers (“none” counts)." }
            if values.contains("") { return "every answer needs a value." }
            if values.contains(where: { $0.contains("\"") || $0.contains("|") }) {
                return "answers cannot contain double quotes or |."
            }
            if values.contains(AIAnswerRecord.noneValue), question.allowsNone { return "“none” is already the exit of that question." }
            if values.contains(VLMPrompt.notApplicable) { return "“n/a” is reserved." }
            if Set(values).count != values.count { return "answers of one question must differ." }
        }
        return nil
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        save()
    }

    private func save() {
        guard problem == nil, draft != lastSaved else { return }
        let snapshot = draft
        if controller.saveAIProfile(assembled(snapshot)) != nil {
            lastSaved = snapshot
        }
    }

    /// The draft as a profile. Keyword ids that no longer exist (deleted
    /// while this window was open) are dropped rather than failing the save.
    private func assembled(_ draft: Draft) -> AIProfile {
        let tree = controller.snapshot?.keywordTree
        func live(_ id: Int64?) -> Int64? { id.flatMap { tree?.node($0) != nil ? $0 : nil } }
        func question(_ q: Draft.Question) -> AIQuestion {
            var answers: [AIAnswer] = []
            if q.kind == .choice {
                answers = q.answers.map { answer in
                    AIAnswer(
                        value: answer.value.trimmingCharacters(in: .whitespaces).lowercased(),
                        keywordId: live(answer.keywordId),
                        stopsProfile: answer.stopsProfile,
                        followUps: answer.followUps.map(question)
                    )
                }
            }
            if q.allowsNone {
                answers.append(AIAnswer(value: AIAnswerRecord.noneValue, stopsProfile: q.noneEnds))
            }
            return AIQuestion(
                text: q.text.trimmingCharacters(in: .whitespaces), kind: q.kind,
                parentKeywordId: q.kind == .open ? live(q.parentKeywordId) : nil, answers: answers
            )
        }
        var record = profile.record
        record.name = draft.name.trimmingCharacters(in: .whitespaces)
        record.instructions = draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIProfile(record: record, questions: draft.questions.map(question))
    }
}

// MARK: - Question card

/// One question with its answers; follow-ups nest recursively inside the
/// answer rows. `label` is the outline number ("2", "2.1"), `gate` the
/// answer this question waits for.
private struct QuestionCard: View {
    @Environment(LibraryController.self) private var controller
    @Binding var question: AIQuestionnaireEditor.Draft.Question
    let label: String
    let gate: String?
    let depth: Int
    let onRemove: () -> Void

    /// Branch colours cycle by depth so nested follow-ups stay tellable.
    static let branchColors: [Color] = [.accentColor, .orange, .purple, .teal, .pink]
    static func branchColor(_ depth: Int) -> Color { branchColors[depth % branchColors.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow
            if question.kind == .choice {
                answerRows
            } else {
                openRows
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(depth == 0 ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(depth == 0 ? Color.primary.opacity(0.08) : Self.branchColor(depth - 1).opacity(0.35))
        )
    }

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let gate {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                    Text("only after “\(gate)”")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Self.branchColor(depth - 1))
            }
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(depth == 0 ? Color.secondary : Self.branchColor(depth - 1), in: Capsule())
                TextField("", text: $question.text, prompt: Text(question.kind == .open ? "Question, e.g. What colour is the dress?" : "Question, e.g. How many people are the subject of the photo?"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $question.kind) {
                    Text("Choices").tag(AIQuestionKind.choice)
                    Text("Open answer").tag(AIQuestionKind.open)
                }
                .labelsHidden()
                .fixedSize()
                .help("Choices: the model picks one of the answers below. Open answer: the model answers in its own words, which become a keyword.")
                Button(action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this question" + (question.descendants.isEmpty ? "" : " and its follow-ups"))
            }
        }
    }

    // MARK: Choices

    private var answerRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($question.answers) { $answer in
                AnswerRow(
                    answer: $answer, questionLabel: label, depth: depth,
                    onRemove: { question.answers.removeAll { $0.id == answer.id } }
                )
            }
            noneRow
            HStack(spacing: 12) {
                Button {
                    question.answers.append(.init())
                } label: {
                    Label("Add Answer", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.leading, 4)
        }
        .padding(.leading, 8)
    }

    /// The "Allow none" checkbox — an exit answer that assigns nothing, for
    /// photos the question does not apply to. Shown as a row so its "Ends"
    /// sits where the other answers have theirs.
    private var noneRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $question.allowsNone) {
                HStack(spacing: 4) {
                    Text("Allow “none”").font(.callout)
                    Text("— the model may answer that nothing applies; assigns no keyword")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
            if question.allowsNone {
                Toggle("Ends", isOn: $question.noneEnds)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help("“none” ends the questionnaire for the photo — e.g. no person makes gender or age moot")
            }
        }
        .padding(.leading, 4)
    }

    // MARK: Open answer

    private var openRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "text.cursor").foregroundStyle(.tertiary)
                Text("The model answers in one or two words; they become a pending keyword under:")
                    .font(.callout)
                    .lineLimit(1)
                KeywordPathField(keywordId: $question.parentKeywordId)
                    .frame(maxWidth: 320)
                    .help("Optional parent keyword for the coined keywords (“COLORS > BLUE”). Leave empty for a top-level keyword.")
            }
            HStack(spacing: 8) {
                Image(systemName: "book").foregroundStyle(.tertiary)
                Text(vocabularyNote).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Toggle(isOn: $question.allowsNone) {
                    HStack(spacing: 4) {
                        Text("Allow “none”").font(.callout)
                        Text("— when the question does not apply").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                Spacer()
                if question.allowsNone {
                    Toggle("Ends", isOn: $question.noneEnds)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .help("“none” ends the questionnaire for the photo")
                }
            }
            .padding(.leading, 4)
        }
        .padding(.leading, 8)
    }

    private var vocabularyNote: String {
        guard let tree = controller.snapshot?.keywordTree else { return "" }
        guard let parentId = question.parentKeywordId, tree.node(parentId) != nil else {
            return "Without a parent keyword the words are matched against, or created among, your top-level keywords. A rejected coinage is removed again unless something else uses it."
        }
        let names = tree.children(of: parentId).compactMap { tree.node($0)?.name }
        if names.isEmpty {
            return "“\(tree.path(of: parentId))” has no keywords yet — the model's words start the vocabulary. Accepted words are offered as the preferred wording on later runs."
        }
        let shown = names.prefix(8).joined(separator: ", ")
        return "Offered to the model as preferred wording: \(shown)\(names.count > 8 ? " and \(names.count - 8) more" : ""). New words are created next to them."
    }
}

// MARK: - Answer row

/// One answer: literal, keyword, Ends, follow-up button — and the follow-up
/// cards underneath, hanging off a guide line in the branch colour.
private struct AnswerRow: View {
    @Binding var answer: AIQuestionnaireEditor.Draft.Answer
    let questionLabel: String
    let depth: Int
    let onRemove: () -> Void

    private var color: Color { QuestionCard.branchColor(depth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary)
                TextField("", text: $answer.value, prompt: Text("answer"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                KeywordPathField(keywordId: $answer.keywordId)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Ends", isOn: $answer.stopsProfile)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help("When chosen, the remaining questions of this questionnaire assign nothing for the photo (e.g. “no person”)")
                Button {
                    answer.followUps.append(.init(answers: [.init(), .init()]))
                } label: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(color)
                .help("Add a follow-up question — asked only when the model chose “\(answer.value.isEmpty ? "this answer" : answer.value)”")
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove answer" + (answer.followUps.isEmpty ? "" : " and its follow-up questions"))
            }
            if !answer.followUps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($answer.followUps) { $followUp in
                        let index = answer.followUps.firstIndex { $0.id == followUp.id } ?? 0
                        QuestionCard(
                            question: $followUp,
                            label: "\(questionLabel).\(index + 1)",
                            gate: answer.value.isEmpty ? "this answer" : answer.value,
                            depth: depth + 1,
                            onRemove: { answer.followUps.removeAll { $0.id == followUp.id } }
                        )
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    // The guide line from the answer down its follow-ups.
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.6))
                        .frame(width: 2)
                        .padding(.leading, 6)
                }
                .padding(.leading, 6)
            }
        }
    }
}
