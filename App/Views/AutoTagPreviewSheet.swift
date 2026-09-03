import BallastCore
import SwiftUI

/// U49: the calibration view — the model's answers for a handful of selected
/// photos, next to their thumbnails and the raw reply, WITHOUT applying
/// anything. The way to tune question wording before a run over thousands.
struct AutoTagPreviewSheet: View {
    @Environment(LibraryController.self) private var controller
    @Environment(AutoTagRunner.self) private var runner
    let state: AutoTagRunner.PreviewState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Auto-Tagging Preview").font(.headline)
                Spacer()
                if state.isRunning {
                    ProgressView(value: Double(state.done), total: Double(max(1, state.total)))
                        .frame(width: 160)
                    Text("\(state.done) of \(state.total)").font(.caption).foregroundStyle(.secondary)
                    Button("Cancel") { runner.cancel() }
                }
            }
            .padding(12)
            Divider()
            if let error = state.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(12)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(state.items) { item in
                        itemView(item)
                        Divider()
                    }
                    if state.items.isEmpty, !state.isRunning, state.error == nil {
                        Text("No answers.").foregroundStyle(.secondary).padding(12)
                    }
                }
                .padding(12)
            }
            Divider()
            HStack {
                Text("Nothing was assigned — this is a preview. Adjust the questions in Settings ▸ AI, then run Auto-Tag Photos from the sidebar.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { runner.dismissPreview() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(state.isRunning)
            }
            .padding(12)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 500, idealHeight: 680)
    }

    private func itemView(_ item: AutoTagRunner.PreviewItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PreviewThumbnail(path: item.path)
                .frame(width: 160, height: 120)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.filename).font(.subheadline.weight(.medium)).lineLimit(1)
                ForEach(Array(item.replies.enumerated()), id: \.offset) { _, reply in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reply.profileName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if reply.answers.isEmpty {
                            Text("Reply could not be read.").font(.caption).foregroundStyle(.orange)
                        }
                        ForEach(Array(reply.answers.enumerated()), id: \.offset) { _, answer in
                            HStack(spacing: 6) {
                                Text(answer.question).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text("→ \(answer.value)").font(.caption.weight(.medium))
                                if let path = answer.keywordPath {
                                    Text(path).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                                }
                            }
                        }
                        DisclosureGroup("Raw reply") {
                            Text(reply.raw)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption2)
                    }
                }
            }
        }
    }
}

private struct PreviewThumbnail: View {
    @Environment(LibraryController.self) private var controller
    let path: String
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .task(id: path) {
            image = await controller.thumbnails?.thumbnail(forPath: path, longEdge: 256)?.image
        }
    }
}
