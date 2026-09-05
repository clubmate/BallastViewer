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

    /// Per destination, measured off the main thread (`stat` on a vanished
    /// network share can block for a long time — review finding). Nil until
    /// the first measurement.
    private(set) var driveStatuses: [UUID: DriveStatus] = [:]

    /// Re-measures every destination; called by Settings ▸ Backup on appear,
    /// on mount/unmount and after a run.
    func refreshDriveStatuses() async {
        let list = destinations
        let measured = await Task.detached(priority: .utility) { () -> [UUID: DriveStatus] in
            var result: [UUID: DriveStatus] = [:]
            for destination in list { result[destination.id] = Self.driveStatus(destination) }
            return result
        }.value
        driveStatuses = measured
    }

    /// Whether a drive destination's folder is reachable right now and how
    /// much room its volume has. Servers report `isConnected` true (checked
    /// only by running). Blocking I/O — call off the main thread.
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

    /// Why a run is refused before it starts (shown as the failed phase).
    static func refusal(
        libraryURL: URL, folders: [FolderRecord], destination: BackupDestination
    ) -> String? {
        switch destination.kind {
        case .drive:
            // Backing up a library that lives INSIDE the destination root would
            // rename the fresh snapshot over the database GRDB has open (every
            // later change lost, a foreign WAL left beside it) — the exact
            // "opened the backup in place" restore flow. A root inside a
            // library folder would be re-imported by the next rescan and
            // copied into itself, one level deeper each run.
            let root = canonicalPath(destination.rootPath)
            let library = canonicalPath(libraryURL.path)
            if library == root || library.hasPrefix(root + "/") {
                return "This library lives inside the backup destination (“\(destination.displayName)”). Open the original library, or choose another destination."
            }
            for folder in folders {
                let path = canonicalPath(folder.path)
                if path == root || path.hasPrefix(root + "/") {
                    return "The folder “\(folder.path)” lies inside the backup destination — it would be copied onto itself."
                }
                if root.hasPrefix(path + "/") {
                    return "The destination lies inside the library folder “\(folder.path)” — the backup would be imported as photos and copied into itself."
                }
            }
        case .server(_, _, _, let path):
            if !RsyncCommand.isRemotePathSafe(path) {
                return "The server folder must not contain line breaks or runs of spaces."
            }
        }
        return nil
    }

    /// `realpath` (Foundation's `resolvingSymlinksInPath` leaves `/tmp` →
    /// `/private/tmp` alone), walking up to the longest existing prefix for a
    /// path that does not exist yet (the backup root before the first run).
    nonisolated static func canonicalPath(_ path: String) -> String {
        let normalized = BackupPlan.normalized(path)
        if let resolved = realpath(normalized, nil) {
            defer { free(resolved) }
            return BackupPlan.normalized(String(cString: resolved))
        }
        let parent = (normalized as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != normalized else { return normalized }
        return (canonicalPath(parent) as NSString).appendingPathComponent((normalized as NSString).lastPathComponent)
    }

    func run(_ destination: BackupDestination, controller: LibraryController, transport: Transport = .auto) {
        guard !isRunning, let library = controller.library, let libraryURL = controller.libraryURL,
              let startSnapshot = controller.snapshot
        else { return }
        summary = nil
        activeDestinationId = destination.id
        if let refusal = Self.refusal(libraryURL: libraryURL, folders: startSnapshot.folders, destination: destination) {
            phase = .failed(refusal)
            return
        }

        var password: String?
        if case .server(let host, let user, _, _) = destination.kind {
            guard let entered = Self.askPassword(user: user, host: host) else {
                activeDestinationId = nil
                return
            }
            password = entered
        }
        let sshPassword = password
        // The library at the start; a switch during the run aborts it.
        let libraryUUID = startSnapshot.meta.libraryUUID

        phase = .preparing("Writing pending changes to files…")
        cancelFlag = CancelFlag()
        let flag = cancelFlag
        let started = Date()
        let relay = ProgressRelay()
        progressRelay = relay

        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }

            await controller.fileWriteThrough?.flushAll()
            await controller.writePipeline?.flush()
            guard !flag.isCancelled else { self.finishCancelled(); return }
            guard let snapshot = controller.snapshot, snapshot.meta.libraryUUID == libraryUUID,
                  controller.libraryURL?.path == libraryURL.path
            else {
                self.phase = .failed("The library changed while the backup was starting — nothing was copied.")
                return
            }
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

            // Reports are numbered so a late hop can never step the bar back
            // or leak into the next run.
            let progress: @Sendable (Int, Int, Int64, Int64) -> Void = { [weak self] done, total, bytesDone, bytesTotal in
                let sequence = relay.next()
                Task { @MainActor in
                    guard let self, self.progressRelay === relay, relay.accept(sequence) else { return }
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
            self.progressRelay = nil

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
            await self.refreshDriveStatuses()
        }
    }

    @ObservationIgnored private var progressRelay: ProgressRelay?

    /// Monotonic sequence for progress hops (see `run`).
    final class ProgressRelay: @unchecked Sendable {
        private let lock = NSLock()
        private var issued = 0
        private var applied = 0

        func next() -> Int {
            lock.lock(); defer { lock.unlock() }
            issued += 1
            return issued
        }

        /// True when `sequence` is newer than anything applied so far.
        func accept(_ sequence: Int) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard sequence > applied else { return false }
            applied = sequence
            return true
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
                if entry.dest.hasSuffix("/library.sqlite") {
                    // A backup library that was opened in place leaves a WAL
                    // beside the file; it must not be replayed into the new
                    // snapshot on the next open.
                    try? fm.removeItem(atPath: entry.dest + "-wal")
                    try? fm.removeItem(atPath: entry.dest + "-shm")
                }
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
    /// a server, ssh gets the password through an askpass helper that reads
    /// a private FIFO fed by this process for the duration of the run — the
    /// password is neither on the command line, nor in a file, nor in the
    /// environment of rsync/ssh.
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
                let below = String(item.relativePath.dropFirst(prefix.count))
                guard RsyncCommand.isListableName(below) else {
                    result.failed.append("\(item.sourcePath): the name contains a line break, which rsync cannot list")
                    continue
                }
                bytesTotal += Int64(st.st_size)
                files.append(below)
            }
            guard !files.isEmpty else { continue }
            let targetDir = (root as NSString).appendingPathComponent(name)
            if server != nil, !RsyncCommand.isRemotePathSafe(targetDir) {
                return .failure("The folder name “\(name)” cannot be sent to the server (line break or runs of spaces).")
            }
            batches.append(Batch(sourceDir: BackupPlan.normalized(folder.path), files: files, targetDir: targetDir))
        }
        batches.append(Batch(sourceDir: staging.path, files: extras.map(\.relativePath), targetDir: root))
        let total = batches.reduce(0) { $0 + $1.files.count }

        var environment = ProcessInfo.processInfo.environment
        var feeder: PasswordFeeder?
        if let server {
            do {
                let started = try PasswordFeeder(directory: staging, password: server.password)
                feeder = started
                environment["SSH_ASKPASS"] = started.scriptPath
                environment["SSH_ASKPASS_REQUIRE"] = "force"
                environment["DISPLAY"] = environment["DISPLAY"] ?? ":0"
                environment["BV_ASKPASS_FIFO"] = started.fifoPath
            } catch {
                return .failure("Could not prepare the ssh helper: \(error.localizedDescription)")
            }
        } else {
            do {
                try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
            } catch {
                return .failure("Could not create “\(root)”: \(error.localizedDescription)")
            }
        }
        defer { feeder?.stop() }

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

            // One blocking reader per pipe (no readabilityHandler: two readers
            // on one descriptor interleave chunks and miscount lines).
            let counter = LineCounter(expected: Set(batch.files))
            let errorBuffer = DataBuffer()
            let batchStart = done
            let plannedBytes = bytesTotal
            let readers = DispatchGroup()
            let stdoutHandle = stdout.fileHandleForReading
            let stderrHandle = stderr.fileHandleForReading
            DispatchQueue.global(qos: .utility).async(group: readers) {
                while let chunk = try? stdoutHandle.read(upToCount: 65_536), !chunk.isEmpty {
                    if counter.consume(chunk) > 0 {
                        progress(batchStart + counter.count, total, 0, plannedBytes)
                    }
                }
            }
            DispatchQueue.global(qos: .utility).async(group: readers) {
                while let chunk = try? stderrHandle.read(upToCount: 65_536), !chunk.isEmpty {
                    errorBuffer.append(chunk)
                }
            }

            do {
                try process.run()
            } catch {
                return .failure("Could not start rsync: \(error.localizedDescription)")
            }
            flag.attach(process)
            process.waitUntilExit()
            flag.attach(nil)
            readers.wait()

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
                if RsyncCommand.isAuthenticationFailure(text) {
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

    /// Feeds the ssh password to the askpass helper through a private FIFO
    /// (mode 0600 in the staging directory). Each ssh invocation runs the
    /// helper once; the helper `cat`s the FIFO, the writer thread here
    /// answers every open with the password and closes. `stop()` unblocks
    /// the writer and removes the FIFO.
    private final class PasswordFeeder: @unchecked Sendable {
        let scriptPath: String
        let fifoPath: String
        private let password: [UInt8]
        private let lock = NSLock()
        private var stopped = false
        private let finished = DispatchSemaphore(value: 0)

        init(directory: URL, password: String) throws {
            let script = directory.appendingPathComponent("askpass.sh")
            let fifo = directory.appendingPathComponent("askpass.fifo")
            try "#!/bin/sh\ncat \"$BV_ASKPASS_FIFO\"\n".write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            guard mkfifo(fifo.path, 0o600) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            scriptPath = script.path
            fifoPath = fifo.path
            self.password = Array((password + "\n").utf8)
            let thread = Thread { [self] in self.serve() }
            thread.name = "BackupService.askpass"
            thread.start()
        }

        private var isStopped: Bool {
            lock.lock(); defer { lock.unlock() }
            return stopped
        }

        private func serve() {
            defer { finished.signal() }
            while !isStopped {
                let fd = open(fifoPath, O_WRONLY)  // blocks until a reader opens
                guard fd >= 0 else { break }
                if !isStopped {
                    password.withUnsafeBufferPointer { buffer in
                        _ = write(fd, buffer.baseAddress, buffer.count)
                    }
                }
                close(fd)
            }
        }

        func stop() {
            lock.lock()
            stopped = true
            lock.unlock()
            // Unblock a writer waiting in open(): become the reader once.
            let fd = open(fifoPath, O_RDONLY | O_NONBLOCK)
            if fd >= 0 {
                var scratch = [UInt8](repeating: 0, count: 256)
                _ = read(fd, &scratch, scratch.count)
                close(fd)
            }
            _ = finished.wait(timeout: .now() + 2)
            unlink(fifoPath)
        }
    }

    /// Counts transferred files in rsync's `-v` output as it streams.
    private final class LineCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private let expected: Set<String>
        private var matched = 0

        init(expected: Set<String>) { self.expected = expected }

        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return matched
        }

        /// Returns how many new matches this chunk produced.
        func consume(_ data: Data) -> Int {
            lock.lock(); defer { lock.unlock() }
            buffer.append(data)
            var newly = 0
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                if expected.contains(line) {
                    matched += 1
                    newly += 1
                }
            }
            return newly
        }
    }

    private final class DataBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()

        var data: Data {
            lock.lock(); defer { lock.unlock() }
            return bytes
        }

        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            bytes.append(chunk)
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
