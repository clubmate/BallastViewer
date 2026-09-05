import BallastCore
import SwiftUI

/// Settings ▸ AI (U49/U50): the master switch, the vision-language model
/// (which one, downloaded or not, add your own by Hugging Face id) and the
/// two run switches. Everything about WHAT is asked — the keyword
/// questionnaires and the system prompt — lives in the AI window (AI ▸
/// Keyword Questionnaires…), which exists while the switch is on.
/// Everything runs on-device; nothing leaves the machine except the
/// one-time model download.
struct AISettingsView: View {
    /// UserDefaults keys of the run settings (read by `AutoTagRunner`).
    static let systemPromptKey = "aiSystemPrompt"
    static let thinkingKey = "aiThinking"
    static let fullResolutionKey = "aiFullResolution"

    /// The system prompt in force: the user's edit, or the default when the
    /// stored one is blank.
    @MainActor static var currentSystemPrompt: String {
        let stored = UserDefaults.standard.string(forKey: systemPromptKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? VLMPrompt.systemPrompt : stored
    }

    @Environment(LibraryController.self) private var controller
    @Environment(VLMModelStore.self) private var models
    @Environment(AutoTagRunner.self) private var runner
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AISettingsView.thinkingKey) private var thinking = false
    @AppStorage(AISettingsView.fullResolutionKey) private var fullResolution = false
    @State private var customRepo = ""
    @State private var pendingModelRemoval: VLMModelStore.ModelInfo?

    var body: some View {
        @Bindable var models = models
        Form {
            Section {
                Toggle("Enable AI auto-tagging", isOn: $models.aiEnabled)
                    .disabled(runner.isRunning)
                if models.aiEnabled {
                    HStack(spacing: 8) {
                        Text("Questionnaires, the system prompt and every auto-tagging action are in the AI menu.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open AI Window…") { openWindow(id: AIWindow.id) }
                            .controlSize(.small)
                            .disabled(controller.snapshot == nil)
                    }
                }
            }
            // Model choice and run switches exist only while AI is on
            // (user request 2026-09-05).
            if models.aiEnabled {
                modelSection
                runSection
            }
        }
        .formStyle(.grouped)
        .alert(
            models.state(of: pendingModelRemoval?.id ?? "") == .ready ? "Remove Model Files" : "Discard Partial Download",
            isPresented: Binding(get: { pendingModelRemoval != nil }, set: { if !$0 { pendingModelRemoval = nil } }),
            presenting: pendingModelRemoval
        ) { model in
            Button("Remove", role: .destructive) { models.remove(model.id) }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text(models.state(of: model.id) == .ready
                ? "Deletes “\(model.title)” (\(model.sizeGB.map { "\($0) GB" } ?? "the weights")) from the shared Hugging Face cache. Other tools using that cache lose it too; it can be downloaded again any time."
                : "Deletes the partial download of “\(model.title)” from the shared Hugging Face cache.")
        }
        .onAppear { models.refreshStates() }
    }

    // MARK: Model

    private var modelSection: some View {
        Section {
            ForEach(models.models) { model in
                modelRow(model)
            }
            HStack(spacing: 8) {
                TextField("", text: $customRepo, prompt: Text("Add a model by Hugging Face id, e.g. mlx-community/Qwen3.5-4B-4bit"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCustom)
                Button("Add Model") { addCustom() }
                    .disabled(customRepo.trimmingCharacters(in: .whitespaces).isEmpty || models.isValidatingCustom)
                if models.isValidatingCustom {
                    ProgressView().controlSize(.small)
                }
            }
            if let error = models.addError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Model")
        } footer: {
            Text("Models are stored in the shared Hugging Face cache (~/.cache/huggingface/hub) and reused by other tools. An interrupted download continues where it stopped. Any MLX-converted vision model with a supported architecture can be added by its repository id. Runs entirely on this Mac — photos never leave the machine.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func modelRow(_ model: VLMModelStore.ModelInfo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                models.selectedId = model.id
            } label: {
                Image(systemName: models.selectedId == model.id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(models.selectedId == model.id ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(runner.isRunning)
            .help("Use this model for auto-tagging")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.title).fontWeight(models.selectedId == model.id ? .semibold : .regular)
                    if let size = model.sizeGB {
                        Text("\(size, format: .number.precision(.fractionLength(1))) GB")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(model.note).font(.caption).foregroundStyle(.secondary)
                if let warning = VLMModelStore.memoryNote(for: model) {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text(model.id).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            modelState(model)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func modelState(_ model: VLMModelStore.ModelInfo) -> some View {
        switch models.state(of: model.id) {
        case .notDownloaded:
            HStack(spacing: 6) {
                Button("Download") { models.download(model.id) }
                if !model.builtIn {
                    Button("Forget") { models.removeCustom(model.id) }
                        .help("Remove from this list (nothing is on disk)")
                }
            }
        case .partial(let bytes):
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Button("Continue Download") { models.download(model.id) }
                    Button("Discard") { pendingModelRemoval = model }
                        .help("Delete the partial download")
                }
                Text("\(Double(bytes) / 1e9, format: .number.precision(.fractionLength(1))) GB already on disk")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        case .downloading(let progress):
            HStack(spacing: 6) {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: progress.fraction, total: 1).frame(width: 160)
                    Text(downloadCaption(progress)).font(.caption2).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button("Cancel") { models.cancelDownload(model.id) }
                    .controlSize(.small)
                    .help("Stops the download; the bytes so far stay and Continue picks up there")
            }
        case .ready:
            HStack(spacing: 6) {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
                Button("Remove") { pendingModelRemoval = model }
                    .disabled(runner.isRunning)
                    .help("Delete the model files from disk")
            }
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 2) {
                Button("Retry") { models.download(model.id) }
                    .help("Continues where the download stopped")
                Text(message).font(.caption2).foregroundStyle(.red)
                    .lineLimit(2).frame(maxWidth: 220, alignment: .trailing)
            }
        }
    }

    /// "1.2 of 6.0 GB · 38 MB/s · about 2 min left" — the rate appears after
    /// the first second, the estimate follows the smoothed rate.
    private func downloadCaption(_ progress: VLMModelStore.DownloadProgress) -> String {
        let gb = { (bytes: Int64) in
            (Double(bytes) / 1e9).formatted(.number.precision(.fractionLength(1)))
        }
        var parts = [progress.total > 0 ? "\(gb(progress.bytes)) of \(gb(progress.total)) GB" : "\(gb(progress.bytes)) GB"]
        if let rate = progress.bytesPerSecond {
            parts.append("\((rate / 1e6).formatted(.number.precision(.fractionLength(rate < 10e6 ? 1 : 0)))) MB/s")
        }
        if let seconds = progress.secondsLeft {
            parts.append(AutoTagStatusSection.timeLeft(seconds))
        }
        return parts.joined(separator: " · ")
    }

    private func addCustom() {
        models.addCustom(repositoryId: customRepo)
        customRepo = ""
    }

    // MARK: Run settings

    private var runSection: some View {
        Section {
            Toggle("Let the model think before answering", isOn: $thinking)
            Text("Off: the model answers directly (a few seconds per photo). On: it first writes a reasoning trace, then answers — several times slower, sometimes more careful on counting and ambiguous scenes.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Send photos at full resolution", isOn: $fullResolution)
            Text("Off: photos are sent at 768 px on the long edge — enough for faces, headcounts and scenes. On: the decoded original goes in (the library holds previews up to about 2K); slower and more memory, helps only with small details.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Run")
        } footer: {
            Text("Changing either switch re-asks the model on the next run (earlier answers stay cached under the old settings).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(runner.isRunning)
    }
}
