import AppKit
import BallastCore
import Darwin
import Foundation
import Observation
import os

/// U53: backups. A backup is a plain copy of every photo file plus a
/// consistent snapshot of `library.sqlite`, laid out flat under
/// `<destination>/BallastViewerBackup/` (see `BackupPlan`). Two transports:
/// a drive (any mounted folder — copied with FileManager, unchanged files
/// skipped by size + mtime) and a server (rsync over ssh, password asked
/// per run through an askpass helper, never stored). Nothing is ever
/// deleted on the destination. Lives app-wide; progress shows in the
/// sidebar's BACKUP section and in Settings ▸ Backup.
///
/// Before copying, the pending metadata write-through is flushed so the
/// files carry the latest keywords, ratings and rotations, and the write
/// pipeline is drained so the snapshot has every committed change.
@MainActor @Observable
final class BackupService {
    enum Phase: Equatable {
        case idle
        case preparing(String)
        case copying(done: Int, total: Int, bytesDone: Int64, bytesTotal: Int64)
        case failed(String)
    }

    /// `.rsync` forces the rsync path onto a drive destination — the test
    /// hook's way to exercise the rsync transport without a server.
    enum Transport { case auto, rsync }

    private enum Keys {
        static let destinations = "backupDestinations"
        static let interval = "backupIntervalDays"
        static let lastRuns = "backupLastRuns"
        static let snoozedUntil = "backupSnoozedUntil"
    }

    static let settingsFilename = "BallastViewer Settings.plist"

    private(set) var phase: Phase = .idle
    /// Human-readable result of the last completed run (dismissable).
    private(set) var summary: String?
    private(set) var activeDestinationId: UUID?

    var isRunning: Bool {
        switch phase {
        case .preparing, .copying: return true
        case .idle, .failed: return false
        }
    }

    var destinations: [BackupDestination] {
        didSet { persistDestinations() }
    }

    /// Reminder interval in days; 0 = never remind.
    var intervalDays: Int {
        didSet { UserDefaults.standard.set(intervalDays, forKey: Keys.interval) }
    }

    private(set) var snoozedUntil: Date?

    struct LibrarySize: Equatable, Sendable {
        var photoCount: Int
        var fileBytes: Int64
        var databaseBytes: Int64
        var missing: Int
        var totalBytes: Int64 { fileBytes + databaseBytes }
    }

    private(set) var librarySize: LibrarySize?
    private(set) var isMeasuring = false
    @ObservationIgnored private var measuredKey: String?

    /// Bumped on volume mount/unmount so drive availability re-renders.
    private(set) var volumeGeneration = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cancelFlag = CancelFlag()
    @ObservationIgnored private var mountObservers: [NSObjectProtocol] = []
    @ObservationIgnored private let logger = Logger(subsystem: "com.bolliboll.ballastviewer", category: "Backup")

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.destinations),
           let list = try? JSONDecoder().decode([BackupDestination].self, from: data) {
            destinations = list
        } else {
            destinations = []
        }
        intervalDays = defaults.object(forKey: Keys.interval) == nil
            ? BackupSchedule.defaultIntervalDays
            : defaults.integer(forKey: Keys.interval)
        snoozedUntil = defaults.object(forKey: Keys.snoozedUntil) as? Date

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            mountObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.volumeGeneration += 1 }
            })
        }
    }

    private func persistDestinations() {
        if let data = try? JSONEncoder().encode(destinations) {
            UserDefaults.standard.set(data, forKey: Keys.destinations)
        }
    }

    // MARK: Last runs / reminder

    private func lastRunKey(libraryUUID: String, destinationId: UUID) -> String {
        "\(libraryUUID)|\(destinationId.uuidString)"
    }

    func lastBackup(libraryUUID: String, destination: BackupDestination) -> Date? {
        let runs = UserDefaults.standard.dictionary(forKey: Keys.lastRuns) ?? [:]
        return runs[lastRunKey(libraryUUID: libraryUUID, destinationId: destination.id)] as? Date
    }

    /// The most recent backup of the library to any configured destination.
    func lastBackup(libraryUUID: String) -> Date? {
        destinations.compactMap { lastBackup(libraryUUID: libraryUUID, destination: $0) }.max()
    }

    private func recordBackup(libraryUUID: String, destination: BackupDestination) {
        var runs = UserDefaults.standard.dictionary(forKey: Keys.lastRuns) ?? [:]
        runs[lastRunKey(libraryUUID: libraryUUID, destinationId: destination.id)] = Date()
        UserDefaults.standard.set(runs, forKey: Keys.lastRuns)
        snoozedUntil = nil
        UserDefaults.standard.removeObject(forKey: Keys.snoozedUntil)
        volumeGeneration += 1  // re-render the "last backup" lines
    }

    func isDue(libraryUUID: String) -> Bool {
        _ = volumeGeneration
        return BackupSchedule.isDue(
            lastBackup: lastBackup(libraryUUID: libraryUUID),
            intervalDays: intervalDays,
            snoozedUntil: snoozedUntil
        )
    }

    /// "Later": hide the notice for a day.
    func snooze(days: Int = 1) {
        snoozedUntil = Date().addingTimeInterval(TimeInterval(days) * 86_400)
        UserDefaults.standard.set(snoozedUntil, forKey: Keys.snoozedUntil)
    }

    func dismissSummary() {
        summary = nil
        if case .failed = phase { phase = .idle }
        activeDestinationId = nil
    }

    // MARK: Drive status

    struct DriveStatus: Equatable {
        var isConnected: Bool
        var freeBytes: Int64?
    }

    /// Whether a drive destination's folder is reachable right now and how
    /// much room its volume has. Servers report `isConnected` true (checked
    /// only by running).
    nonisolated static func driveStatus(_ destination: BackupDestination) -> DriveStatus {
        guard case .drive(let path) = destination.kind else { return DriveStatus(isConnected: true, freeBytes: nil) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return DriveStatus(isConnected: false, freeBytes: nil)
        }
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return DriveStatus(isConnected: true, freeBytes: values?.volumeAvailableCapacityForImportantUsage)
    }

    // MARK: Library size

    /// Sums the photo files and the database for Settings ▸ Backup. Cached
    /// per library + photo count; re-measured when either changes.
    func measure(controller: LibraryController) async {
        guard let snapshot = controller.snapshot, let libraryURL = controller.libraryURL else {
            librarySize = nil
            measuredKey = nil
            return
        }
        let key = "\(snapshot.meta.libraryUUID)|\(snapshot.photos.count)"
        guard key != measuredKey, !isMeasuring else { return }
        isMeasuring = true
        defer { isMeasuring = false }
        let paths = snapshot.photos.map(\.path)
        let dbURL = libraryURL.appendingPathComponent("library.sqlite")
        let size = await Task.detached(priority: .utility) { () -> LibrarySize in
            var bytes: Int64 = 0
            var missing = 0
            var st = stat()
            for path in paths {
                if stat(path, &st) == 0 {
                    bytes += Int64(st.st_size)
                } else {
                    missing += 1
                }
            }
            var db: Int64 = 0
            for suffix in ["", "-wal"] where stat(dbURL.path + suffix, &st) == 0 {
                db += Int64(st.st_size)
            }
            return LibrarySize(photoCount: paths.count, fileBytes: bytes, databaseBytes: db, missing: missing)
        }.value
        librarySize = size
        measuredKey = key
    }

    // MARK: Running

    func cancel() {
        cancelFlag.cancel()
    }

    func run(_ destination: BackupDestination, controller: LibraryController, transport: Transport = .auto) {
        guard !isRunning, let library = controller.library, let libraryURL = controller.libraryURL else { return }

        var password: String?
        if case .server(let host, let user, _, _) = destination.kind {
            guard let entered = Self.askPassword(user: user, host: host) else { return }
            password = entered
        }
        let sshPassword = password

        summary = nil
        activeDestinationId = destination.id
        phase = .preparing("Writing pending changes to files…")
        cancelFlag = CancelFlag()
        let flag = cancelFlag
        let started = Date()

        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }

            await controller.fileWriteThrough?.flushAll()
            await controller.writePipeline?.flush()
            guard !flag.isCancelled else { self.finishCancelled(); return }
            guard let snapshot = controller.snapshot else {
                self.phase = .failed("No library open.")
                return
            }
            let libraryUUID = snapshot.meta.libraryUUID
            let folders = snapshot.folders
            let plan = BackupPlan.make(folders: folders, photos: snapshot.photos)
            let packageName = libraryURL.lastPathComponent

            self.phase = .preparing("Snapshotting the library…")
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("BallastViewerBackup-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            let dbCopy = staging.appendingPathComponent(packageName).appendingPathComponent("library.sqlite")
            let settingsCopy = staging.appendingPathComponent(Self.settingsFilename)
            do {
                try await Task.detached(priority: .userInitiated) {
                    try library.snapshotDatabase(to: dbCopy)
                    Self.exportSettings(to: settingsCopy)
                }.value
            } catch {
                self.phase = .failed("Could not snapshot the library: \(error.localizedDescription)")
                return
            }
            guard !flag.isCancelled else { self.finishCancelled(); return }

            // Everything that is not a photo: the snapshot and the settings,
            // staged under their final relative paths.
            let extras = [
                BackupPlan.Item(sourcePath: dbCopy.path, relativePath: "\(packageName)/library.sqlite"),
                BackupPlan.Item(sourcePath: settingsCopy.path, relativePath: Self.settingsFilename),
            ]

            let progress: @Sendable (Int, Int, Int64, Int64) -> Void = { [weak self] done, total, bytesDone, bytesTotal in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    self.phase = .copying(done: done, total: total, bytesDone: bytesDone, bytesTotal: bytesTotal)
                }
            }

            let outcome: Outcome
            switch (destination.kind, transport) {
            case (.drive(let drivePath), .auto):
                self.phase = .preparing("Comparing with the backup…")
                outcome = await Task.detached(priority: .userInitiated) {
                    Self.copyToDrive(
                        plan: plan, extras: extras, drivePath: drivePath, root: destination.rootPath,
                        flag: flag, progress: progress
                    )
                }.value
            case (.drive, .rsync):
                self.phase = .preparing("Starting rsync…")
                outcome = await Task.detached(priority: .userInitiated) {
                    Self.pushWithRsync(
                        plan: plan, folders: folders, extras: extras, staging: staging,
                        root: destination.rootPath, server: nil, flag: flag, progress: progress
                    )
                }.value
            case (.server(let host, let user, let port, _), _):
                self.phase = .preparing("Connecting to \(host)…")
                let server = ServerAccess(host: host, user: user, port: port, password: sshPassword ?? "")
                outcome = await Task.detached(priority: .userInitiated) {
                    Self.pushWithRsync(
                        plan: plan, folders: folders, extras: extras, staging: staging,
                        root: destination.rootPath, server: server, flag: flag, progress: progress
                    )
                }.value
            }

            if flag.isCancelled {
                self.finishCancelled()
                return
            }
            switch outcome {
            case .failure(let message):
                self.phase = .failed(message)
                self.logger.error("Backup failed: \(message, privacy: .public)")
            case .success(let result):
                let minutes = Int(Date().timeIntervalSince(started) / 60)
                let size = result.bytes > 0 ? " (\(Self.format(bytes: result.bytes)))" : ""
                var parts = ["Backed up \(result.copied) file\(result.copied == 1 ? "" : "s")\(size) to \(destination.displayName)"]
                if result.skipped > 0 { parts.append("\(result.skipped) unchanged") }
                if result.missing > 0 { parts.append("\(result.missing) missing on disk") }
                if !result.failed.isEmpty { parts.append("\(result.failed.count) failed") }
                var text = parts.joined(separator: " · ")
                if minutes >= 1 { text += " · \(minutes) min" }
                if let first = result.failed.first { text += "\nFirst failure: \(first)" }
                self.summary = text
                self.phase = .idle
                if result.failed.isEmpty {
                    self.recordBackup(libraryUUID: libraryUUID, destination: destination)
                }
            }
        }
    }

    private func finishCancelled() {
        summary = "Backup cancelled."
        phase = .idle
    }

    nonisolated static func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: Results

    struct RunResult: Sendable {
        var copied = 0
        var skipped = 0
        var missing = 0
        var failed: [String] = []
        var bytes: Int64 = 0
    }

    enum Outcome: Sendable {
        case success(RunResult)
        case failure(String)
    }

    struct ServerAccess: Sendable {
        var host: String
        var user: String
        var port: Int
        var password: String
    }

    /// Cancellation shared with the detached worker (Task cancellation does
    /// not cross into `Task.detached`), plus the rsync process to terminate.
    final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var process: Process?

        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let running = process
            lock.unlock()
            running?.terminate()
        }

        func attach(_ process: Process?) {
            lock.lock()
            self.process = process
            let cancelledNow = cancelled
            lock.unlock()
            if cancelledNow { process?.terminate() }
        }
    }

    // MARK: Drive transport

    /// Off the MainActor. Pass 1 compares every file with its copy (size +
    /// mtime, 2 s tolerance for FAT/exFAT sticks) and checks free space
    /// against what has to be copied; pass 2 copies via a temp name +
    /// atomic rename so an interrupted copy never leaves a truncated file
    /// under the final name.
    nonisolated private static func copyToDrive(
        plan: BackupPlan,
        extras: [BackupPlan.Item],
        drivePath: String,
        root: String,
        flag: CancelFlag,
        progress: @Sendable (Int, Int, Int64, Int64) -> Void
    ) -> Outcome {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: drivePath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure("“\(drivePath)” is not connected.")
        }
        do {
            try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        } catch {
            return .failure("Could not create “\(root)”: \(error.localizedDescription)")
        }

        var result = RunResult()
        struct Pending { var source: String; var dest: String; var size: Int64; var mtime: timespec }
        var pending: [Pending] = []
        var bytesTotal: Int64 = 0
        var src = stat()
        var dst = stat()
        for item in plan.items + extras {
            if flag.isCancelled { return .success(result) }
            guard stat(item.sourcePath, &src) == 0 else {
                result.missing += 1
                continue
            }
            let dest = (root as NSString).appendingPathComponent(item.relativePath)
            if stat(dest, &dst) == 0, dst.st_size == src.st_size,
               abs(dst.st_mtimespec.tv_sec - src.st_mtimespec.tv_sec) <= 2 {
                result.skipped += 1
                continue
            }
            pending.append(Pending(source: item.sourcePath, dest: dest, size: Int64(src.st_size), mtime: src.st_mtimespec))
            bytesTotal += Int64(src.st_size)
        }

        if let free = driveStatus(BackupDestination(kind: .drive(path: drivePath))).freeBytes, free < bytesTotal {
            return .failure("Not enough room on “\(drivePath)”: the backup needs \(format(bytes: bytesTotal)), \(format(bytes: free)) free.")
        }

        var createdDirectories: Set<String> = []
        var bytesDone: Int64 = 0
        var lastReport = Date.distantPast
        progress(0, pending.count, 0, bytesTotal)
        for (index, entry) in pending.enumerated() {
            if flag.isCancelled { break }
            let directory = (entry.dest as NSString).deletingLastPathComponent
            if !createdDirectories.contains(directory) {
                do {
                    try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    createdDirectories.insert(directory)
                } catch {
                    result.failed.append("\(entry.dest): \(error.localizedDescription)")
                    continue
                }
            }
            let temp = (directory as NSString).appendingPathComponent(".\((entry.dest as NSString).lastPathComponent).bvpart")
            do {
                try? fm.removeItem(atPath: temp)
                try fm.copyItem(atPath: entry.source, toPath: temp)
                // Keep the source's mtime: it is the "unchanged" key next time.
                var times = [timespec(tv_sec: entry.mtime.tv_sec, tv_nsec: entry.mtime.tv_nsec), entry.mtime]
                _ = utimensat(AT_FDCWD, temp, &times, 0)
                guard rename(temp, entry.dest) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                result.copied += 1
                result.bytes += entry.size
                bytesDone += entry.size
            } catch {
                try? fm.removeItem(atPath: temp)
                result.failed.append("\(entry.source): \(error.localizedDescription)")
            }
            let now = Date()
            if now.timeIntervalSince(lastReport) >= 0.2 || index == pending.count - 1 {
                lastReport = now
                progress(index + 1, pending.count, bytesDone, bytesTotal)
            }
        }
        return .success(result)
    }

    // MARK: rsync transport

    /// Off the MainActor. One rsync run per library folder (`--files-from`
    /// with the plan's relative paths) plus one for the staged extras. With
    /// a server, ssh gets the password through an askpass helper script
    /// that prints an environment variable — the password never touches
    /// the command line or a file.
    nonisolated private static func pushWithRsync(
        plan: BackupPlan,
        folders: [FolderRecord],
        extras: [BackupPlan.Item],
        staging: URL,
        root: String,
        server: ServerAccess?,
        flag: CancelFlag,
        progress: @escaping @Sendable (Int, Int, Int64, Int64) -> Void
    ) -> Outcome {
        let fm = FileManager.default
        var result = RunResult()

        // Batches: (source directory, relative paths below it, target directory).
        struct Batch { var sourceDir: String; var files: [String]; var targetDir: String }
        var batches: [Batch] = []
        var st = stat()
        var bytesTotal: Int64 = 0
        for folder in folders {
            guard let folderId = folder.id, let name = plan.folderNames[folderId] else { continue }
            let prefix = name + "/"
            var files: [String] = []
            for item in plan.items where item.relativePath.hasPrefix(prefix) {
                guard stat(item.sourcePath, &st) == 0 else {
                    result.missing += 1
                    continue
                }
                bytesTotal += Int64(st.st_size)
                files.append(String(item.relativePath.dropFirst(prefix.count)))
            }
            guard !files.isEmpty else { continue }
            batches.append(Batch(
                sourceDir: BackupPlan.normalized(folder.path), files: files,
                targetDir: (root as NSString).appendingPathComponent(name)
            ))
        }
        batches.append(Batch(sourceDir: staging.path, files: extras.map(\.relativePath), targetDir: root))
        let total = batches.reduce(0) { $0 + $1.files.count }

        var askpass: URL?
        var environment = ProcessInfo.processInfo.environment
        if let server {
            let script = staging.appendingPathComponent("askpass.sh")
            do {
                try "#!/bin/sh\nprintf '%s\\n' \"$BV_SSH_PASSWORD\"\n".write(to: script, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            } catch {
                return .failure("Could not prepare the ssh helper: \(error.localizedDescription)")
            }
            askpass = script
            environment["SSH_ASKPASS"] = script.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = environment["DISPLAY"] ?? ":0"
            environment["BV_SSH_PASSWORD"] = server.password
        } else {
            do {
                try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
            } catch {
                return .failure("Could not create “\(root)”: \(error.localizedDescription)")
            }
        }
        _ = askpass

        var done = 0
        progress(0, total, 0, bytesTotal)
        for (index, batch) in batches.enumerated() {
            if flag.isCancelled { break }
            let list = staging.appendingPathComponent("files-\(index).txt")
            do {
                try (batch.files.joined(separator: "\n") + "\n").write(to: list, atomically: true, encoding: .utf8)
            } catch {
                return .failure("Could not write the file list: \(error.localizedDescription)")
            }
            if server == nil {
                try? fm.createDirectory(atPath: batch.targetDir, withIntermediateDirectories: true)
            }
            let target = server.map { RsyncCommand.remoteTarget(user: $0.user, host: $0.host, path: batch.targetDir) }
                ?? batch.targetDir
            let arguments = RsyncCommand.arguments(
                filesFrom: list.path, sourceDir: batch.sourceDir, target: target,
                remotePath: server == nil ? nil : batch.targetDir, sshPort: server?.port
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: RsyncCommand.executable)
            process.arguments = arguments
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let expected = Set(batch.files)
            let counter = LineCounter(expected: expected)
            let batchStart = done
            let plannedBytes = bytesTotal
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let newlySeen = counter.consume(data)
                if newlySeen > 0 {
                    progress(batchStart + counter.count, total, 0, plannedBytes)
                }
            }
            let errorBuffer = DataBuffer()
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { errorBuffer.append(data) }
            }

            do {
                try process.run()
            } catch {
                return .failure("Could not start rsync: \(error.localizedDescription)")
            }
            flag.attach(process)
            process.waitUntilExit()
            flag.attach(nil)
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            _ = counter.consume(stdout.fileHandleForReading.readDataToEndOfFile())
            errorBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())

            let transferred = counter.count
            done += batch.files.count
            result.copied += transferred
            result.skipped += batch.files.count - transferred
            progress(done, total, 0, bytesTotal)

            if flag.isCancelled { break }
            let status = process.terminationStatus
            // 23/24: partial transfer (a file vanished mid-run) — the rest landed.
            if status != 0, status != 23, status != 24 {
                let text = String(decoding: errorBuffer.data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if text.contains("Permission denied") || text.contains("permission denied") {
                    return .failure("The server refused the password (or the user name is wrong).")
                }
                if text.contains("Host key verification failed") {
                    return .failure("The server's host key changed — check ~/.ssh/known_hosts.")
                }
                let tail = text.split(separator: "\n").suffix(3).joined(separator: "\n")
                return .failure("rsync failed (exit \(status))" + (tail.isEmpty ? "." : ":\n\(tail)"))
            }
        }
        // rsync -v does not report bytes per file; the plan's total stands in.
        result.bytes = result.copied == total ? bytesTotal : 0
        return .success(result)
    }

    /// Counts transferred files in rsync's `-v` output as it streams.
    private final class LineCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private let expected: Set<String>
        private(set) var count = 0

        init(expected: Set<String>) { self.expected = expected }

        /// Returns how many new matches this chunk produced.
        func consume(_ data: Data) -> Int {
            lock.lock(); defer { lock.unlock() }
            buffer.append(data)
            var newly = 0
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                    .trimmingCharacters(in: .whitespaces)
                buffer.removeSubrange(buffer.startIndex...newline)
                if expected.contains(line) {
                    count += 1
                    newly += 1
                }
            }
            return newly
        }
    }

    private final class DataBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var data = Data()

        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
        }
    }

    // MARK: Helpers

    /// The app's UserDefaults domain (shortcuts, MIDI bindings, appearance…)
    /// as a plist next to the backup — the part of the setup that does not
    /// live in the library.
    nonisolated private static func exportSettings(to url: URL) {
        guard let bundleId = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: bundleId),
              let data = try? PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0)
        else { return }
        try? data.write(to: url)
    }

    /// Modal password prompt for a server run. Nil = cancelled.
    private static func askPassword(user: String, host: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Password for \(user)@\(host)"
        alert.informativeText = "BallastViewer sends the password to ssh for this backup only. It is not stored."
        alert.addButton(withTitle: "Back Up")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Password"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
