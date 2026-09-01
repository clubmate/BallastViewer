import BallastCore
import SwiftUI

/// Settings ▸ AI (U48): the model download, the match threshold, and the
/// keyword prompts ("what does HANDY look like?"). Prompts are opt-in — a
/// keyword without one never takes part in auto-tagging. The runs themselves
/// start from the sidebar (right-click a smart collection or ALL PHOTOS ▸
/// Auto-Tag Photos); progress shows in the sidebar's AUTO-TAGGING section.
/// Everything runs on-device; nothing leaves the machine except the one-time
/// model download.
struct AISettingsView: View {
    static let defaultThreshold = 0.25
    /// UserDefaults key of the match threshold — shared with the sidebar
    /// (run start) and the score diagnostic hook.
    static let thresholdKey = "aiSuggestionThreshold"

    @Environment(LibraryController.self) private var controller
    @Environment(EmbeddingModelStore.self) private var models
    @AppStorage(AISettingsView.thresholdKey) private var threshold = AISettingsView.defaultThreshold
    @State private var newKeywordId: Int64?
    @State private var newPrompt = ""

    var body: some View {
        Form {
            modelSection
            thresholdSection
            promptsSection
        }
        .formStyle(.grouped)
    }

    // MARK: Model

    private var modelSection: some View {
        Section("Model") {
            switch models.state {
            case .notDownloaded:
                LabeledContent("MobileCLIP-S2", value: "Not downloaded (~200 MB)")
                HStack {
                    Button("Download Model") { models.download() }
                    Button("Locate Manual Download…") { models.locateManualDownload() }
                }
            case .downloading(let fraction):
                ProgressView(value: fraction) {
                    Text("Downloading MobileCLIP-S2…")
                }
            case .compiling:
                ProgressView { Text("Compiling model…") }
            case .ready:
                LabeledContent("MobileCLIP-S2") {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                HStack {
                    Button("Retry Download") { models.download() }
                    Button("Locate Manual Download…") { models.locateManualDownload() }
                }
            }
            Text("Runs entirely on this Mac. Photos never leave the machine.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Threshold

    private var thresholdSection: some View {
        Section("Sensitivity") {
            HStack(spacing: 12) {
                Slider(value: $threshold, in: 0.15 ... 0.40) {
                    Text("Match Threshold: \(threshold, format: .number.precision(.fractionLength(2)))")
                }
                Button("Reset") { threshold = Self.defaultThreshold }
                    .disabled(abs(threshold - Self.defaultThreshold) < 0.001)
                    .help("Back to the default (\(Self.defaultThreshold, format: .number.precision(.fractionLength(2))))")
            }
            Text("Lower finds more photos (more mistakes), higher finds fewer (more precise).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Prompts

    private var describedRows: [(id: Int64, path: String, prompt: String)] {
        guard let tree = controller.snapshot?.keywordTree else { return [] }
        return tree.allIdsDepthFirst().compactMap { id in
            guard let prompt = tree.node(id)?.aiDescription else { return nil }
            return (id: id, path: tree.path(of: id), prompt: prompt)
        }
    }

    /// Every keyword not yet described, in tree order with full paths.
    private var selectableKeywords: [(id: Int64, path: String)] {
        guard let tree = controller.snapshot?.keywordTree else { return [] }
        return tree.allIdsDepthFirst().compactMap { id in
            guard tree.node(id)?.aiDescription == nil else { return nil }
            return (id: id, path: tree.path(of: id))
        }
    }

    private var promptsSection: some View {
        Section {
            // One Form row for the whole table: the grouped form lays out
            // direct section children with its own label/control heuristic,
            // which fights the fixed keyword column + full-width prompt field.
            VStack(spacing: 10) {
                if describedRows.isEmpty {
                    Text(controller.snapshot == nil
                        ? "Open a library first."
                        : "No keywords set up for auto-tagging yet — add one below.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(describedRows, id: \.id) { row in
                    DescribedKeywordRow(id: row.id, path: row.path, initialPrompt: row.prompt)
                }
                Divider()
                addRow
            }
        } header: {
            Text("Auto-Tagging Keywords (\(describedRows.count))")
        } footer: {
            Text("Describe in ENGLISH what a matching photo shows, caption-style: “a person using a phone”. Separate independent looks of the SAME keyword with | — “a person using a phone | a red car” matches either. Then right-click a smart collection (or ALL PHOTOS) in the sidebar and choose Auto-Tag Photos.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Shared first-column width so the configured rows and the add row line
    /// up as a proper table.
    static let keywordColumnWidth: CGFloat = 180

    private var addRow: some View {
        HStack(spacing: 8) {
            Picker("", selection: $newKeywordId) {
                Text("Choose Keyword…").tag(Int64?.none)
                ForEach(selectableKeywords, id: \.id) { keyword in
                    Text(keyword.path).tag(Int64?.some(keyword.id))
                }
            }
            .labelsHidden()
            .frame(width: Self.keywordColumnWidth, alignment: .leading)
            TextField("Prompt", text: $newPrompt)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .onSubmit(addPrompt)
            Button {
                addPrompt()
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(newKeywordId == nil
                || newPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Add keyword to auto-tagging")
        }
    }

    private func addPrompt() {
        let prompt = newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = newKeywordId, !prompt.isEmpty else { return }
        controller.setKeywordAIDescription(id, description: prompt)
        newKeywordId = nil
        newPrompt = ""
    }
}

/// One configured keyword: path label, editable prompt (committed on submit /
/// focus loss — not per keystroke, each commit is a synchronous DB write),
/// and a remove button that takes the keyword out of auto-tagging.
private struct DescribedKeywordRow: View {
    @Environment(LibraryController.self) private var controller
    let id: Int64
    let path: String
    let initialPrompt: String
    @State private var prompt = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Head-truncated: deep paths ("PEOPLE > … > ANNA") keep their
            // meaningful tail visible; the full path shows on mouseover.
            Text(path)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(width: AISettingsView.keywordColumnWidth, alignment: .leading)
                .help(path)
            TextField("", text: $prompt)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
            Button {
                controller.setKeywordAIDescription(id, description: nil)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove from auto-tagging (the keyword itself stays)")
        }
        .onAppear { prompt = initialPrompt }
        .onChange(of: initialPrompt) { _, fresh in
            if !focused { prompt = fresh }
        }
    }

    private func commit() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != initialPrompt else { return }
        // A blanked field would silently drop the keyword — keep the last
        // prompt instead; removal is the explicit minus button.
        guard !trimmed.isEmpty else {
            prompt = initialPrompt
            return
        }
        controller.setKeywordAIDescription(id, description: trimmed)
    }
}
