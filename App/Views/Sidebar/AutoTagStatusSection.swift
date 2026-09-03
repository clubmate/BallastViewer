import BallastCore
import SwiftUI

/// U48/U49: live status of an auto-tag run at the sidebar's bottom (same recipe
/// as the WRITING FILES section). Visible while a run prepares/scans, and
/// briefly afterwards to show the result (dismissed with ✕). The runs start
/// from the sidebar context menus; this section is their only progress UI.
struct AutoTagStatusSection: View {
    @Environment(AutoTagRunner.self) private var runner

    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                Divider()
                header
                content
            }
        }
    }

    private var isVisible: Bool {
        runner.isRunning || runner.summary != nil || isFailed
    }

    private var isFailed: Bool {
        if case .failed = runner.phase { return true }
        return false
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").font(.caption2)
            Text("AUTO-TAGGING")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            if runner.isRunning {
                Button("Cancel") { runner.cancel() }
                    .buttonStyle(.plain)
                    .font(.caption)
            } else {
                Button {
                    runner.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch runner.phase {
            case .loadingModel(let fraction):
                ProgressView(value: fraction, total: 1)
                    .progressViewStyle(.linear)
                Text("Loading the model…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .scanning(let done, let total, let found):
                ProgressView(value: Double(done), total: Double(max(1, total)))
                    .progressViewStyle(.linear)
                Text("\(done) of \(total) photos — \(found) suggestion\(found == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .idle:
                if let summary = runner.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}
