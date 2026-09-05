import BallastCore
import SwiftUI

/// U53: the BACKUP section at the sidebar's bottom (same recipe as
/// AUTO-TAGGING / WRITING FILES). Shows while a backup runs (progress +
/// Cancel), afterwards with the result (dismissable), and — the reminder —
/// whenever the library's last backup is older than the interval in
/// Settings ▸ Backup, with Back Up Now and Later (a day of quiet).
struct BackupStatusSection: View {
    @Environment(LibraryController.self) private var controller
    @Environment(BackupService.self) private var backup
    @Environment(SettingsRouter.self) private var settingsRouter
    @Environment(\.openSettings) private var openSettings

    private var libraryUUID: String? { controller.snapshot?.meta.libraryUUID }

    private var isDue: Bool {
        guard let uuid = libraryUUID else { return false }
        return backup.isDue(libraryUUID: uuid)
    }

    private var isFailed: Bool {
        if case .failed = backup.phase { return true }
        return false
    }

    var body: some View {
        if backup.isRunning || backup.summary != nil || isFailed || isDue {
            VStack(spacing: 0) {
                Divider()
                header
                content
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "externaldrive.badge.timemachine").font(.caption2)
            Text("BACKUP")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            if backup.isRunning {
                Button("Cancel") { backup.cancel() }
                    .buttonStyle(.plain)
                    .font(.caption)
            } else if backup.summary != nil || isFailed {
                Button {
                    backup.dismissSummary()
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
        VStack(alignment: .leading, spacing: 6) {
            switch backup.phase {
            case .preparing(let text):
                ProgressView().controlSize(.small)
                Text(text).font(.caption).foregroundStyle(.secondary)
            case .copying(let done, let total, let bytesDone, let bytesTotal):
                ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                    .progressViewStyle(.linear)
                Text(Self.progressText(done: done, total: total, bytesDone: bytesDone, bytesTotal: bytesTotal))
                    .font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                if isDue { reminder }
            case .idle:
                if let summary = backup.summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                } else if isDue {
                    reminder
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var reminder: some View {
        if let uuid = libraryUUID {
            if let date = backup.lastBackup(libraryUUID: uuid) {
                Text("Last backup " + date.formatted(.relative(presentation: .named)) + ".")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("This library has never been backed up.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        HStack(spacing: 8) {
            if backup.destinations.isEmpty {
                Button("Set Up Backup…") {
                    settingsRouter.selectedTab = .backup
                    openSettings()
                }
                .controlSize(.small)
            } else if backup.destinations.count == 1, let only = backup.destinations.first {
                Button("Back Up Now") { backup.run(only, controller: controller) }
                    .controlSize(.small)
                    .disabled(controller.isBusy)
            } else {
                Menu("Back Up Now") {
                    ForEach(backup.destinations) { destination in
                        Button(destination.displayName) { backup.run(destination, controller: controller) }
                    }
                }
                .controlSize(.small)
                .fixedSize()
                .disabled(controller.isBusy)
            }
            Button("Later") { backup.snooze() }
                .controlSize(.small)
                .help("Hide this for a day")
        }
    }

    /// "1,234 of 5,000 files · 2.1 GB of 8.4 GB" (bytes omitted when the
    /// transport does not report them — rsync).
    static func progressText(done: Int, total: Int, bytesDone: Int64, bytesTotal: Int64) -> String {
        var text = "\(done) of \(total) file\(total == 1 ? "" : "s")"
        if bytesTotal > 0, bytesDone > 0 {
            text += " · \(BackupService.format(bytes: bytesDone)) of \(BackupService.format(bytes: bytesTotal))"
        }
        return text
    }
}
