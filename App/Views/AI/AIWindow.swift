import BallastCore
import SwiftUI

/// U50: the AI window (AI ▸ Keyword Questionnaires…) — everything about WHAT
/// the model is asked, in a window of its own because it outgrew a settings
/// tab: the questionnaires of the open library (sidebar), the editor of the
/// selected one (detail), the system prompt, and a status bar with the
/// model in use. Resizable; the size is remembered by the window system.
/// Model management and the run switches stay in Settings ▸ AI.
struct AIWindow: View {
    static let id = "aiKeywording"

    enum Selection: Hashable {
        case profile(Int64)
        case systemPrompt
    }

    @Environment(LibraryController.self) private var controller
    @Environment(CenterViewModel.self) private var center
    @Environment(VLMModelStore.self) private var models
    @Environment(AutoTagRunner.self) private var runner
    @Environment(SettingsRouter.self) private var settingsRouter
    @Environment(\.openSettings) private var openSettings
    @State private var selection: Selection?
    @State private var pendingDeletion: AIProfile?

    private var profiles: [AIProfile] { controller.snapshot?.aiProfiles ?? [] }

    private var selectedProfile: AIProfile? {
        guard case .profile(let id) = selection else { return nil }
        return profiles.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
            } detail: {
                detail
            }
            // Below the split view, not a safe-area inset: the sidebar column
            // ignores the inset and would hide its +/− bar behind the bar.
            statusBar
        }
        .navigationTitle("AI Keywording")
        .toolbar { toolbar }
        .frame(minWidth: 860, minHeight: 560)
        .onChange(of: profiles.map(\.id)) { _, ids in
            // The selected questionnaire was deleted (or the library switched).
            if case .profile(let id) = selection, !ids.contains(id) { selection = nil }
        }
        .onAppear {
            if selection == nil, let first = profiles.first?.id { selection = .profile(first) }
        }
        .alert(
            "Delete Questionnaire",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { profile in
            Button("Delete", role: .destructive) {
                if let id = profile.id { controller.deleteAIProfile(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("“\(profile.name)” and its questions are removed from this library. Suggestions already made stay.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            profileList
            Divider()
            HStack(spacing: 2) {
                Button {
                    addProfile()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .help("New questionnaire")
                .disabled(controller.snapshot == nil || runner.isRunning)
                Button {
                    pendingDeletion = selectedProfile
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .help("Delete the selected questionnaire")
                .disabled(selectedProfile == nil || runner.isRunning)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var profileList: some View {
        List(selection: $selection) {
            Section("Keyword Questionnaires") {
                ForEach(profiles, id: \.id) { profile in
                    profileRow(profile)
                        .tag(Selection.profile(profile.id ?? -1))
                }
                if profiles.isEmpty {
                    Text(controller.snapshot == nil ? "Open a library first." : "None yet — add one below.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("General") {
                Label("System Prompt", systemImage: "text.quote")
                    .tag(Selection.systemPrompt)
            }
        }
        .listStyle(.sidebar)
    }

    private func profileRow(_ profile: AIProfile) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { profile.enabled },
                set: { if let id = profile.id { controller.setAIProfileEnabled(id, $0) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(runner.isRunning)
            .help(profile.enabled ? "Asked on every run" : "Switched off — not asked")
            Text(profile.name.isEmpty ? "Untitled" : profile.name)
                .lineLimit(1)
                .foregroundStyle(profile.enabled ? .primary : .secondary)
            Spacer(minLength: 4)
            Text("\(profile.allQuestions.count)")
                .font(.caption2).monospacedDigit()
                .foregroundStyle(.secondary)
                .help("\(profile.allQuestions.count) question\(profile.allQuestions.count == 1 ? "" : "s")")
        }
    }

    private func addProfile() {
        let draft = AIProfile(
            record: AIProfileRecord(name: "New Questionnaire", instructions: AIProfile.defaultInstructions),
            questions: []
        )
        if let saved = controller.saveAIProfile(draft), let id = saved.id {
            selection = .profile(id)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if controller.snapshot == nil {
            ContentUnavailableView("No Library Open", systemImage: "books.vertical", description: Text("Questionnaires live in the library. Open one from the Library menu."))
        } else if let profile = selectedProfile {
            AIQuestionnaireEditor(profile: profile)
                .id(profile.id)
                .disabled(runner.isRunning)
        } else if selection == .systemPrompt {
            SystemPromptPane()
                .disabled(runner.isRunning)
        } else {
            ContentUnavailableView {
                Label("Keyword Questionnaires", systemImage: "sparkles")
            } description: {
                Text("A questionnaire is a list of questions the model answers about every photo. Each answer can assign one of your keywords; an open question lets the model's own words become a keyword; a follow-up question is asked only after a particular answer.\n\nSelect a questionnaire on the left, or add one with +.")
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                runner.preview(controller: controller, models: models, photos: selectedPhotos)
            } label: {
                Label("Preview on Selection", systemImage: "eye")
            }
            .help("Show the model's answers for the selected photos (up to \(AutoTagRunner.previewLimit)) without assigning anything")
            .disabled(!center.hasAnchor || runner.isRunning || runner.preview != nil)
            Button {
                runner.run(controller: controller, models: models, photos: selectedPhotos, scopeName: "the selection")
            } label: {
                Label("Auto-Tag Selection", systemImage: "sparkles")
            }
            .help("Ask every enabled questionnaire about the selected photos")
            .disabled(!center.hasAnchor || runner.isRunning)
        }
    }

    private var selectedPhotos: [PhotoRecord] {
        guard let snapshot = controller.snapshot else { return [] }
        let selected = center.selection.selectedIds
        return AutoTagRunner.photos(withIds: center.visiblePhotos.map(\.id).filter { selected.contains($0) }, in: snapshot)
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu").foregroundStyle(.secondary)
            if let model = models.selected {
                Text(model.title).font(.caption)
                modelStateLabel(model)
            } else {
                Text("No model selected").font(.caption).foregroundStyle(.secondary)
            }
            Button("Model Settings…") {
                settingsRouter.selectedTab = .ai
                openSettings()
            }
            .controlSize(.small)
            Spacer()
            runStatus
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private func modelStateLabel(_ model: VLMModelStore.ModelInfo) -> some View {
        switch models.state(of: model.id) {
        case .ready:
            Label("Downloaded", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .downloading(let progress):
            Text("Downloading \(Int(progress.fraction * 100)) %").font(.caption).foregroundStyle(.secondary)
        case .partial:
            Label("Partly downloaded", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
        case .notDownloaded:
            Label("Not downloaded", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
        case .failed:
            Label("Download failed", systemImage: "xmark.circle").font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var runStatus: some View {
        switch runner.phase {
        case .loadingModel:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading the model…").font(.caption).foregroundStyle(.secondary)
            }
        case .scanning(let done, let total, let found, _):
            HStack(spacing: 6) {
                ProgressView(value: Double(done), total: Double(max(1, total))).frame(width: 120)
                Text("\(done) of \(total) — \(found) suggestion\(found == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                Button("Cancel") { runner.cancel() }.controlSize(.small)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).lineLimit(1)
        case .idle:
            if let summary = runner.summary {
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(summary)
            }
        }
    }
}

/// The system prompt — sent before every questionnaire's instructions.
private struct SystemPromptPane: View {
    @AppStorage(AISettingsView.systemPromptKey) private var systemPrompt = VLMPrompt.systemPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("System Prompt").font(.title3.weight(.semibold))
                Spacer()
                Button("Reset to Default") { systemPrompt = VLMPrompt.systemPrompt }
                    .disabled(systemPrompt == VLMPrompt.systemPrompt)
            }
            Text("Sent before every questionnaire's instructions and questions — the model's ground rules. Leave it blank to use the default. Changing it re-asks the model on the next run (earlier answers stay cached under the old prompt).")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $systemPrompt)
                .font(.body)
                .frame(minHeight: 120, maxHeight: 260)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            if systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Blank — the default is used:\n\(VLMPrompt.systemPrompt)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }
}
