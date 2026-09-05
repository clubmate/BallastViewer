import BallastCore
import SwiftUI

/// U54: "Ask Model on Selection…" — type a question, get the model's
/// answer in prose for every selected photo. Nothing is assigned and
/// nothing is cached; the point is to learn what the model sees (and how
/// it needs to be asked) before a question goes into a questionnaire.
/// Questions stack newest first so the latest answers are at the top.
struct AskModelSheet: View {
    @Environment(LibraryController.self) private var controller
    @Environment(VLMModelStore.self) private var models
    @Environment(AutoTagRunner.self) private var runner
    let state: AutoTagRunner.AskState
    @State private var question = ""
    @FocusState private var questionFocused: Bool

    /// A question may be typed and sent while the model is still loading —
    /// it is answered as soon as the load finishes.
    private var canAsk: Bool {
        !state.isAnswering && state.error == nil
            && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ask the Model").font(.headline)
                Text("\(state.photos.count) photo\(state.photos.count == 1 ? "" : "s") · \(state.modelTitle)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if state.isLoadingModel {
                    ProgressView(value: state.loadProgress).frame(width: 160)
                    Text("Loading model…").font(.caption).foregroundStyle(.secondary)
                } else if state.isAnswering, let round = state.rounds.first {
                    ProgressView(value: Double(round.answers.count), total: Double(max(1, state.photos.count)))
                        .frame(width: 160)
                    Text("\(round.answers.count) of \(state.photos.count)").font(.caption).foregroundStyle(.secondary)
                    Button("Cancel") { runner.cancelAsk() }
                }
            }
            .padding(12)
            Divider()
            // The photos being asked about, upright as the model sees them.
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(state.photos) { photo in
                        UprightThumbnail(path: photo.path, orientation: photo.orientation)
                            .frame(width: 96, height: 72)
                            .help(photo.filename)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            Divider()
            HStack(alignment: .top, spacing: 8) {
                TextField(
                    "Ask anything about these photos — e.g. “Are two people greeting each other? How can you tell?”",
                    text: $question, axis: .vertical
                )
                .lineLimit(1 ... 5)
                .textFieldStyle(.roundedBorder)
                .focused($questionFocused)
                .onSubmit { submit() }
                .disabled(state.error != nil)
                Button("Ask") { submit() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canAsk)
            }
            .padding(12)
            if let error = state.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.bottom, 12)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(state.rounds) { round in
                        roundView(round)
                        Divider()
                    }
                    if state.rounds.isEmpty, state.error == nil {
                        Text("Answers appear here. The model answers in plain English and sees each photo on its own — ask about what is visible, then use the wording that works in a questionnaire.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
                .padding(12)
            }
            Divider()
            HStack {
                Text("Nothing is assigned or cached. Thinking and resolution follow Settings ▸ AI.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { runner.dismissAsk() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 540, idealHeight: 720)
        .onAppear { questionFocused = true }
    }

    private func submit() {
        guard canAsk else { return }
        runner.ask(question, controller: controller, models: models)
        question = ""
        questionFocused = true
    }

    private func roundView(_ round: AutoTagRunner.AskRound) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "questionmark.bubble").foregroundStyle(.secondary)
                Text(round.question).font(.subheadline.weight(.semibold)).textSelection(.enabled)
            }
            ForEach(state.photos) { photo in
                HStack(alignment: .top, spacing: 12) {
                    UprightThumbnail(path: photo.path, orientation: photo.orientation)
                        .frame(width: 120, height: 90)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(photo.filename).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                        if let answer = round.answers.first(where: { $0.id == photo.id }) {
                            Text(answer.text)
                                .font(.callout)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let thinking = answer.thinking {
                                DisclosureGroup("Thinking") {
                                    Text(thinking)
                                        .font(.system(.caption2, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.caption2)
                            }
                        } else if round.isRunning {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Waiting…").font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Not answered — cancelled.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
