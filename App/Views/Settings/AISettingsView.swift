import BallastCore
import SwiftUI

/// Settings ▸ AI (U48): teach keywords ("what does HANDY mean?"), manage the
/// local MobileCLIP model, calibrate the match threshold, and preview scores
/// for the current grid selection. Descriptions are opt-in — a keyword
/// without one never takes part in AI suggestions. Everything runs on-device;
/// nothing leaves the machine except the one-time model download.
struct AISettingsView: View {
    @Environment(LibraryController.self) private var controller
    @Environment(CenterViewModel.self) private var center
    @Environment(EmbeddingModelStore.self) private var models
    @Environment(SuggestionRunner.self) private var runner
    @AppStorage("aiSuggestionThreshold") private var threshold = 0.25
    @State private var filter = ""
    @State private var preview = PreviewState.idle

    var body: some View {
        Form {
            modelSection
            thresholdSection
            descriptionsSection
            previewSection
            runSection
        }
        .formStyle(.grouped)
    }

    // MARK: Suggestion run (Stage 2)

    private var runSection: some View {
        Section("Suggestions") {
            HStack {
                Button("Suggest Keywords for All Photos") {
                    runner.run(controller: controller, models: models, threshold: Float(threshold))
                }
                .disabled(models.state != .ready || runner.isRunning)
                if runner.isRunning {
                    Button("Cancel") { runner.cancel() }
                }
            }
            switch runner.phase {
            case .idle:
                if let summary = runner.summary {
                    Text(summary).font(.caption)
                } else {
                    Text("Scores every photo against every described keyword. Matches attach as PENDING chips in the inspector — accept ✓ or reject ✗ each one; nothing is written to files until you accept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .preparing:
                ProgressView { Text("Embedding keyword descriptions…") }
            case .scanning(let done, let total, let found):
                ProgressView(value: Double(done), total: Double(max(1, total))) {
                    Text("Scanning photo \(done + 1) of \(total) — \(found) suggestions so far")
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
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
            Slider(value: $threshold, in: 0.15 ... 0.40) {
                Text("Match Threshold: \(threshold, format: .number.precision(.fractionLength(2)))")
            }
            Text("Lower finds more photos (more mistakes), higher finds fewer (more precise). Use the preview below to calibrate.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Descriptions

    private var describedCount: Int {
        controller.snapshot?.keywordTree.allRecords.filter { $0.aiDescription != nil }.count ?? 0
    }

    private var keywordRows: [(id: Int64, path: String, description: String)] {
        guard let tree = controller.snapshot?.keywordTree else { return [] }
        let folded = filter.lowercased()
        return tree.allIdsDepthFirst().compactMap { id in
            guard let node = tree.node(id) else { return nil }
            let path = tree.path(of: id)
            if !folded.isEmpty, !path.lowercased().contains(folded),
               !(node.aiDescription?.lowercased().contains(folded) ?? false) {
                return nil
            }
            return (id: id, path: path, description: node.aiDescription ?? "")
        }
    }

    private var descriptionsSection: some View {
        Section {
            TextField("Filter keywords", text: $filter)
                .textFieldStyle(.roundedBorder)
            if keywordRows.isEmpty {
                Text(controller.snapshot == nil ? "Open a library first." : "No keywords match.")
                    .foregroundStyle(.secondary)
            }
            ForEach(keywordRows, id: \.id) { row in
                KeywordDescriptionField(id: row.id, path: row.path, initialText: row.description)
            }
        } header: {
            Text("Keyword Descriptions (\(describedCount) described)")
        } footer: {
            Text("Describe in ENGLISH what a matching photo shows, e.g. “someone talking on a phone”. Keywords without a description are never suggested.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Preview

    private enum PreviewState: Equatable {
        case idle
        case running(Int, Int)
        case done([PreviewRow])
        case failed(String)
    }

    private struct PreviewRow: Equatable, Identifiable {
        var id: Int64
        var filename: String
        var scores: [PreviewScore]
    }

    private struct PreviewScore: Equatable, Identifiable {
        var id: Int64
        var path: String
        var score: Float
    }

    private var previewSection: some View {
        Section("Preview") {
            HStack {
                Button("Preview Matches for Selection") { runPreview() }
                    .disabled(models.state != .ready || isPreviewRunning)
                Spacer()
                Text("\(center.selection.selectedIds.count) selected")
                    .foregroundStyle(.secondary)
            }
            switch preview {
            case .idle:
                Text("Select photos in the grid, then preview their scores per described keyword. Scores at or above the threshold would become suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .running(let done, let total):
                ProgressView(value: Double(done), total: Double(max(1, total))) {
                    Text("Scoring photo \(done + 1) of \(total)…")
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .done(let rows):
                if rows.isEmpty {
                    Text("Nothing to score.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.filename).fontWeight(.medium)
                        ForEach(row.scores) { entry in
                            HStack(spacing: 6) {
                                Image(
                                    systemName: entry.score >= Float(threshold)
                                        ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundStyle(
                                    entry.score >= Float(threshold) ? .green : .secondary
                                )
                                Text(entry.path)
                                Spacer()
                                Text("\(entry.score, format: .number.precision(.fractionLength(3)))")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var isPreviewRunning: Bool {
        if case .running = preview { return true }
        return false
    }

    /// The CLIP prompt for one description. CLIP was trained on caption-style
    /// text, so bare fragments score better wrapped in "a photo of …".
    static func promptText(for description: String) -> String {
        let lowered = description.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lowered.hasPrefix("a photo") ? lowered : "a photo of \(lowered)"
    }

    private func runPreview() {
        guard let snapshot = controller.snapshot, let thumbnails = controller.thumbnails else {
            preview = .failed("Open a library first.")
            return
        }
        guard let service = models.service() else {
            preview = .failed("The model is not ready.")
            return
        }
        let described = snapshot.keywordTree.allRecords
            .filter { $0.aiDescription != nil && $0.id != nil }
        guard !described.isEmpty else {
            preview = .failed("No keyword has a description yet.")
            return
        }
        let selectedIds = center.selection.selectedIds
        // The preview is a calibration tool, not the bulk run — cap it so the
        // settings window stays responsive.
        let photos = Array(
            snapshot.photos.filter { $0.id.map(selectedIds.contains) ?? false }.prefix(24)
        )
        guard !photos.isEmpty else {
            preview = .failed("Select photos in the grid first.")
            return
        }
        let tree = snapshot.keywordTree
        let libraryUUID = snapshot.meta.libraryUUID
        preview = .running(0, photos.count)
        Task {
            do {
                var specs: [(path: String, embedding: [Float])] = []
                for record in described {
                    let embedding = try await service.textEmbedding(
                        Self.promptText(for: record.aiDescription ?? "")
                    )
                    specs.append((path: tree.path(of: record.id!), embedding: embedding))
                }
                let store = try EmbeddingStore(libraryUUID: libraryUUID)
                var rows: [PreviewRow] = []
                for (index, photo) in photos.enumerated() {
                    preview = .running(index, photos.count)
                    guard let box = await thumbnails.thumbnail(forPath: photo.path, longEdge: 256)
                    else { continue }
                    let mtime = EmbeddingStore.mtime(of: photo.path)
                    let vector: [Float]
                    if let cached = try await store.embedding(
                        forPath: photo.path, mtime: mtime,
                        modelVersion: EmbeddingModelStore.modelVersion
                    ) {
                        vector = cached
                    } else {
                        vector = try await service.imageEmbedding(box, orientation: photo.orientation)
                        try await store.store(
                            vector, forPath: photo.path, mtime: mtime,
                            modelVersion: EmbeddingModelStore.modelVersion
                        )
                    }
                    let scores = specs.enumerated()
                        .map { offset, spec in
                            PreviewScore(
                                id: Int64(offset), path: spec.path,
                                score: EmbeddingMath.cosine(vector, spec.embedding)
                            )
                        }
                        .sorted { $0.score > $1.score }
                    rows.append(PreviewRow(id: photo.id ?? 0, filename: photo.filename, scores: scores))
                }
                preview = .done(rows)
            } catch {
                preview = .failed(error.localizedDescription)
            }
        }
    }

}

/// One keyword row: derived path label + description field. Commits on
/// submit and on focus loss — not per keystroke (each commit is a
/// synchronous DB write).
private struct KeywordDescriptionField: View {
    @Environment(LibraryController.self) private var controller
    let id: Int64
    let path: String
    let initialText: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(path) {
            TextField("No description — not suggested", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .multilineTextAlignment(.leading)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
        }
        .onAppear { text = initialText }
        .onChange(of: initialText) { _, fresh in
            if !focused { text = fresh }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != initialText else { return }
        controller.setKeywordAIDescription(id, description: trimmed.isEmpty ? nil : trimmed)
    }
}
