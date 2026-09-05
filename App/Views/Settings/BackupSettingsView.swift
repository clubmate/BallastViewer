import AppKit
import BallastCore
import SwiftUI

/// Settings ▸ Backup (U53): how big the library is, where backups go, when
/// to be reminded. Runs start here, from the Library menu or from the
/// sidebar's BACKUP notice; progress shows in both places.
struct BackupSettingsView: View {
    @Environment(LibraryController.self) private var controller
    @Environment(BackupService.self) private var backup

    @State private var addingServer = false
    @State private var serverDraft = ServerDraft()
    @State private var pendingRemoval: BackupDestination?

    struct ServerDraft {
        var host = ""
        var user = ""
        var port = "22"
        var path = ""

        var isValid: Bool {
            !host.trimmingCharacters(in: .whitespaces).isEmpty
                && !user.trimmingCharacters(in: .whitespaces).isEmpty
                && !path.trimmingCharacters(in: .whitespaces).isEmpty
                && Int(port).map { (1...65_535).contains($0) } == true
        }
    }

    private var libraryUUID: String? { controller.snapshot?.meta.libraryUUID }

    var body: some View {
        @Bindable var backup = backup
        Form {
            librarySection
            destinationsSection
            Section {
                Picker("Remind me after", selection: $backup.intervalDays) {
                    Text("Never").tag(0)
                    ForEach([7, 14, 30, 60, 90], id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
            } footer: {
                Text("A BACKUP notice appears in the sidebar when the library's last backup is older than this. It has a Back Up Now button.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: measureKey) { await backup.measure(controller: controller) }
        .sheet(isPresented: $addingServer) { serverSheet }
        .alert(
            "Remove Destination",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { destination in
            Button("Remove", role: .destructive) {
                backup.destinations.removeAll { $0.id == destination.id }
            }
            Button("Cancel", role: .cancel) {}
        } message: { destination in
            Text("Forget “\(destination.displayName)” as a backup destination? Files already backed up there stay.")
        }
    }

    /// Re-measure when the library or its photo count changes.
    private var measureKey: String {
        "\(libraryUUID ?? "")|\(controller.snapshot?.photos.count ?? 0)"
    }

    // MARK: Library

    @ViewBuilder
    private var librarySection: some View {
        Section("Library") {
            if let url = controller.libraryURL, let snapshot = controller.snapshot {
                LabeledContent("Library", value: controller.displayName(for: url))
                LabeledContent("Photos") {
                    Text("\(snapshot.photos.count) in \(snapshot.folders.count) folder\(snapshot.folders.count == 1 ? "" : "s")")
                }
                LabeledContent("Space needed") {
                    if let size = backup.librarySize, size.photoCount == snapshot.photos.count {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(BackupService.format(bytes: size.totalBytes)).fontWeight(.semibold)
                            Text("\(BackupService.format(bytes: size.fileBytes)) photo files · \(BackupService.format(bytes: size.databaseBytes)) database")
                                .font(.caption).foregroundStyle(.secondary)
                            if size.missing > 0 {
                                Text("\(size.missing) file\(size.missing == 1 ? "" : "s") missing on disk — not backed up")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Text("Measuring…").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Last backup") {
                    if let uuid = libraryUUID, let date = backup.lastBackup(libraryUUID: uuid) {
                        Text(date, format: .dateTime.day().month().year().hour().minute())
                    } else {
                        Text("Never").foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No library open").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Destinations

    @ViewBuilder
    private var destinationsSection: some View {
        Section {
            if backup.destinations.isEmpty {
                Text("No destinations yet. Add a drive (USB disk, stick, network share) or a server.")
                    .foregroundStyle(.secondary)
            }
            ForEach(backup.destinations) { destination in
                destinationRow(destination)
            }
            statusRow
            HStack {
                Button("Add Drive…") { addDrive() }
                Button("Add Server…") {
                    serverDraft = ServerDraft()
                    addingServer = true
                }
            }
        } header: {
            Text("Destinations")
        } footer: {
            Text("A backup is a plain copy: every photo file goes to <destination>/\(BackupPlan.rootFolderName)/<folder name>/…, the library file lands next to those folders. Unchanged files are skipped, nothing is ever deleted on the destination. To restore, open the library file from the backup and use Relink Folder… in Settings ▸ Libraries if the photos moved. Servers are reached with rsync over ssh; the password is asked each time and never stored.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func destinationRow(_ destination: BackupDestination) -> some View {
        // Re-read on mount/unmount and after a run.
        let _ = backup.volumeGeneration
        let status = BackupService.driveStatus(destination)
        return HStack(spacing: 10) {
            Image(systemName: destination.isServer ? "server.rack" : "externaldrive")
                .foregroundStyle(status.isConnected ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusLine(destination, status: status))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Back Up Now") { backup.run(destination, controller: controller) }
                .controlSize(.small)
                .disabled(!canRun || !status.isConnected)
            Button {
                pendingRemoval = destination
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(backup.isRunning && backup.activeDestinationId == destination.id)
        }
    }

    private var canRun: Bool {
        controller.isLibraryOpen && !backup.isRunning && !controller.isBusy
    }

    private func statusLine(_ destination: BackupDestination, status: BackupService.DriveStatus) -> String {
        var parts: [String] = []
        if destination.isServer {
            parts.append("Server")
        } else if status.isConnected {
            parts.append(status.freeBytes.map { "Connected · \(BackupService.format(bytes: $0)) free" } ?? "Connected")
        } else {
            parts.append("Not connected")
        }
        if let uuid = libraryUUID {
            if let date = backup.lastBackup(libraryUUID: uuid, destination: destination) {
                parts.append("Last backup " + date.formatted(.relative(presentation: .named)))
            } else {
                parts.append("Never backed up")
            }
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusRow: some View {
        switch backup.phase {
        case .preparing(let text):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { backup.cancel() }.controlSize(.small)
            }
        case .copying(let done, let total, let bytesDone, let bytesTotal):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                HStack {
                    Text(BackupStatusSection.progressText(done: done, total: total, bytesDone: bytesDone, bytesTotal: bytesTotal))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { backup.cancel() }.controlSize(.small)
                }
            }
        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                Spacer()
                Button("Dismiss") { backup.dismissSummary() }.controlSize(.small)
            }
        case .idle:
            if let summary = backup.summary {
                HStack(alignment: .top, spacing: 8) {
                    Label(summary, systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") { backup.dismissSummary() }.controlSize(.small)
                }
            }
        }
    }

    private func addDrive() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Backup Drive or Folder"
        panel.message = "The backup goes into a “\(BackupPlan.rootFolderName)” folder inside the chosen location."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        guard !backup.destinations.contains(where: { $0.kind == .drive(path: path) }) else { return }
        backup.destinations.append(BackupDestination(kind: .drive(path: path)))
    }

    // MARK: Server sheet

    private var serverSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Server").font(.headline)
            Form {
                TextField("Host", text: $serverDraft.host, prompt: Text("nas.local or 192.168.1.10"))
                TextField("User", text: $serverDraft.user)
                TextField("Port", text: $serverDraft.port)
                TextField("Folder on the server", text: $serverDraft.path, prompt: Text("/volume1/backups"))
            }
            .formStyle(.columns)
            Text("Backups go to <folder>/\(BackupPlan.rootFolderName)/ on the server via rsync over ssh. rsync must be installed there. You are asked for the password on every run.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { addingServer = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    backup.destinations.append(BackupDestination(kind: .server(
                        host: serverDraft.host.trimmingCharacters(in: .whitespaces),
                        user: serverDraft.user.trimmingCharacters(in: .whitespaces),
                        port: Int(serverDraft.port) ?? 22,
                        path: serverDraft.path.trimmingCharacters(in: .whitespaces)
                    )))
                    addingServer = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!serverDraft.isValid)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
