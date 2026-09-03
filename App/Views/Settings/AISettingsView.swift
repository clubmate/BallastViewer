import BallastCore
import SwiftUI

/// Settings ▸ AI (U49): the vision-language model (which one, downloaded or
/// not, add your own by Hugging Face id) and the auto-tagging PROFILES — a
/// questionnaire per photo genre whose answers map to keywords. Runs start
/// from the sidebar (right-click a smart collection or ALL PHOTOS ▸ Auto-Tag
/// Photos); progress shows in the sidebar's AUTO-TAGGING section.
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
    @AppStorage(AISettingsView.systemPromptKey) private var systemPrompt = VLMPrompt.systemPrompt
    @AppStorage(AISettingsView.thinkingKey) private var thinking = false
    @AppStorage(AISettingsView.fullResolutionKey) private var fullResolution = false
    @State private var customRepo = ""
    @State private var editing: AIProfile?
    @State private var pendingDeletion: AIProfile?
    @State private var pendingModelRemoval: VLMModelStore.ModelInfo?
    @State private var importNote: String?

    var body: some View {
        Form {
            modelSection
            promptSection
            profilesSection
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { profile in
            AIProfileEditor(profile: profile) { saved in
                controller.saveAIProfile(saved)
            }
        }
        .alert(
            "Delete Profile",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { profile in
            Button("Delete", role: .destructive) {
                if let id = profile.id { controller.deleteAIProfile(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("“\(profile.name)” and its questions are removed. Suggestions already made stay.")
        }
        .alert(
            "Remove Model Files",
            isPresented: Binding(get: { pendingModelRemoval != nil }, set: { if !$0 { pendingModelRemoval = nil } }),
            presenting: pendingModelRemoval
        ) { model in
            Button("Remove", role: .destructive) { models.remove(model.id) }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text("Deletes “\(model.title)” (\(model.sizeGB.map { "\($0) GB" } ?? "the weights")) from the shared Hugging Face cache. Other tools using that cache lose it too; it can be downloaded again any time.")
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
            Text("Models are stored in the shared Hugging Face cache (~/.cache/huggingface/hub) and reused by other tools. Any MLX-converted vision model with a supported architecture can be added by its repository id. Runs entirely on this Mac — photos never leave the machine.")
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
        case .downloading(let fraction):
            HStack(spacing: 6) {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: fraction, total: 1).frame(width: 120)
                    Text("\(Int(fraction * 100)) %").font(.caption2).foregroundStyle(.secondary)
                }
                Button("Cancel") { models.cancelDownload(model.id) }
                    .controlSize(.small)
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
                Text(message).font(.caption2).foregroundStyle(.red)
                    .lineLimit(2).frame(maxWidth: 220, alignment: .trailing)
            }
        }
    }

    private func addCustom() {
        models.addCustom(repositoryId: customRepo)
        customRepo = ""
    }

    // MARK: Prompt & run settings

    private var promptSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("System prompt").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { systemPrompt = VLMPrompt.systemPrompt }
                        .controlSize(.small)
                        .disabled(systemPrompt == VLMPrompt.systemPrompt)
                }
                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            }
            Toggle("Let the model think before answering", isOn: $thinking)
            Text("Off: the model answers directly (a few seconds per photo). On: it first writes a reasoning trace, then answers — several times slower, sometimes more careful on counting and ambiguous scenes.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Send photos at full resolution", isOn: $fullResolution)
            Text("Off: photos are sent at 768 px on the long edge — enough for faces, headcounts and scenes. On: the decoded original goes in (the library holds previews up to about 2K); slower and more memory, helps only with small details.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Prompt & Run")
        } footer: {
            Text("The system prompt is sent before every profile's instructions and questions. Changing any of these settings re-asks the model on the next run (earlier answers stay cached under the old settings).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(runner.isRunning)
    }

    // MARK: Profiles

    private var profiles: [AIProfile] { controller.snapshot?.aiProfiles ?? [] }

    private var profilesSection: some View {
        Section {
            if controller.snapshot == nil {
                Text("Open a library first.").foregroundStyle(.secondary)
            } else if profiles.isEmpty {
                Text("No profile yet. A profile is a list of questions the model answers about every photo — each answer can assign a keyword.")
                    .foregroundStyle(.secondary)
            }
            ForEach(profiles, id: \.id) { profile in
                profileRow(profile)
            }
            HStack(spacing: 8) {
                Button("New Profile") {
                    editing = AIProfile(
                        record: AIProfileRecord(name: "New Profile", instructions: AIProfile.defaultInstructions),
                        questions: [AIQuestion(record: AIQuestionRecord(profileId: 0, text: ""), answers: [])]
                    )
                }
                Button("Add Example Profile (People)") {
                    editing = AIProfile.starter()
                }
                .help("Six questions — people count, gender, age, angle, face cut off, lighting — with the keywords still to be mapped")
                Button("Import…") { importProfile() }
                    .help("Load a profile exported from another library; keyword paths that do not exist here stay unmapped")
            }
            .disabled(controller.snapshot == nil)
            if let importNote {
                Text(importNote).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Auto-Tagging Profiles (\(profiles.count))")
        } footer: {
            Text("Every enabled profile is asked once per photo. Then right-click a smart collection (or ALL PHOTOS) in the sidebar and choose Auto-Tag Photos; the answers arrive as pending suggestions to review photo by photo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func profileRow(_ profile: AIProfile) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { profile.enabled },
                set: { if let id = profile.id { controller.setAIProfileEnabled(id, $0) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(runner.isRunning)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).fontWeight(.medium)
                Text(profileSummary(profile)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Export…") { exportProfile(profile) }
                .help("Save the questionnaire as JSON (keywords by path) to reuse in another library")
            Button("Edit…") { editing = profile }
                .disabled(runner.isRunning)
            Button {
                pendingDeletion = profile
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(runner.isRunning)
            .help("Delete profile")
        }
        .padding(.vertical, 2)
    }

    private func exportProfile(_ profile: AIProfile) {
        guard let tree = controller.snapshot?.keywordTree else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(profile.name).ballastprofile.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try AIProfileExport(profile: profile, tree: tree).encoded().write(to: url, options: .atomic)
        } catch {
            controller.errorMessage = "Could not export the profile: \(error.localizedDescription)"
        }
    }

    private func importProfile() {
        guard let tree = controller.snapshot?.keywordTree else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = try AIProfileExport.decode(try Data(contentsOf: url))
            let resolved = document.resolved(in: tree)
            editing = resolved.profile
            importNote = resolved.unresolvedPaths.isEmpty
                ? nil
                : "Not in this library, left unmapped: \(resolved.unresolvedPaths.joined(separator: ", "))"
        } catch {
            controller.errorMessage = "Could not read the profile: \(error.localizedDescription)"
        }
    }

    private func profileSummary(_ profile: AIProfile) -> String {
        let questions = profile.questions.count
        let mapped = profile.questions.flatMap(\.answers).filter { $0.keywordId != nil }.count
        var parts = ["\(questions) question\(questions == 1 ? "" : "s")", "\(mapped) answer\(mapped == 1 ? "" : "s") mapped to keywords"]
        if mapped == 0 { parts.append("assigns nothing yet") }
        return parts.joined(separator: " · ")
    }
}

/// `id: Int64?` serves as the identity; unsaved drafts share nil, which is
/// fine for one sheet at a time.
extension AIProfile: Identifiable {}
