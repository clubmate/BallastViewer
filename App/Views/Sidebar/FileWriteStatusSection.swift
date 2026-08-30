import BallastCore
import SwiftUI

/// Collapsible status section at the sidebar's bottom (same recipe as the
/// inspector's KEYWORDS section, U29): visible ONLY during a bulk write run
/// — the Lightroom import's queued file writes, or (U46) any change that
/// leaves ≥ `MetadataWriteThrough.bulkRunThreshold` photos pending at once,
/// such as renaming a keyword hundreds of photos carry. Everyday
/// single-photo write-throughs never show it. Shows a progress bar
/// over the run plus any failed files; disappears when the run drains.
/// Expanded by default; purely informative (the writes run regardless).
struct FileWriteStatusSection: View {
    @Environment(LibraryController.self) private var controller
    @AppStorage("sidebarFileWriteExpanded") private var isExpanded = true

    var body: some View {
        if let writer = controller.fileWriteThrough,
           writer.isBulkRun,
           writer.pendingCount > 0 || !writer.failedPaths.isEmpty {
            VStack(spacing: 0) {
                Divider()
                header(writer)
                if isExpanded {
                    content(writer)
                }
            }
        }
    }

    private func header(_ writer: MetadataWriteThrough) -> some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Text("WRITING FILES")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                if !isExpanded, writer.pendingCount > 0 {
                    Text("\(writer.pendingCount)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.secondary.opacity(0.2)))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func content(_ writer: MetadataWriteThrough) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if writer.pendingCount > 0 {
                ProgressView(value: progressValue(writer))
                    .progressViewStyle(.linear)
                Text("\(writer.completedCount) of \(writer.runTotal) photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !writer.failedPaths.isEmpty {
                Label(
                    "\(writer.failedPaths.count) file\(writer.failedPaths.count == 1 ? "" : "s") failed — retried on next change or open",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func progressValue(_ writer: MetadataWriteThrough) -> Double {
        guard writer.runTotal > 0 else { return 0 }
        return Double(writer.completedCount) / Double(writer.runTotal)
    }
}
