import AppKit
import BallastCore
import Observation

/// BallastViewer ▸ Check for Updates…: fetches the latest GitHub release
/// (public repo, no auth), compares its build number against
/// `CFBundleVersion` (both are the CI's commit count) and installs on
/// confirmation: download the zip into the container, unpack with ditto,
/// trash the running bundle, move the new one into its place, relaunch.
///
/// Sandbox: replacing the bundle needs write access to its parent folder
/// (usually /Applications). The first install asks once via NSOpenPanel and
/// keeps a security-scoped bookmark; every later update is fully automatic.
/// A download through the app carries no quarantine flag, so the ad-hoc
/// signed release relaunches without Gatekeeper friction.
@MainActor @Observable
final class AppUpdater {
    private static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/clubmate/BallastViewer/releases/latest")!
    private static let installFolderBookmarkKey = "updateInstallFolderBookmark"

    private(set) var isWorking = false
    /// Non-nil while the zip downloads — drives the progress bar overlay
    /// (0…1, or indeterminate 0 when the server sends no content length).
    private(set) var downloadProgress: Double?

    func checkForUpdates() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            await run()
        }
    }

    private var currentBuild: Int {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            .flatMap(Int.init) ?? 0
    }

    private var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
    }

    private func run() async {
        let release: UpdateRelease
        do {
            var request = URLRequest(url: Self.latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            release = try UpdateFeed.parseLatestRelease(data)
        } catch {
            alert(
                "Could not check for updates.",
                info: "The release feed was not reachable.\n\(error.localizedDescription)"
            )
            return
        }

        guard release.buildNumber > currentBuild else {
            alert(
                "BallastViewer is up to date.",
                info: "Version \(currentVersion) is the latest release."
            )
            return
        }

        let notes = release.notes.map { String($0.prefix(700)) } ?? ""
        guard confirm(
            "BallastViewer \(release.version) is available.",
            info: "You have \(currentVersion). Install and relaunch now?"
                + (notes.isEmpty ? "" : "\n\n\(notes)"),
            action: "Install"
        ) else { return }

        do {
            try await install(release)
        } catch {
            alert("The update could not be installed.", info: error.localizedDescription)
        }
    }

    // MARK: Install

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private func install(_ release: UpdateRelease) async throws {
        // Download + unpack in the container (no permission needed, and the
        // file never touches a quarantine-flagging browser path).
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("update-\(release.tag)", isDirectory: true)
        try? FileManager.default.removeItem(at: workDir)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let zip = workDir.appendingPathComponent("update.zip")
        downloadProgress = 0
        defer { downloadProgress = nil }
        try await Self.download(from: release.zipURL, to: zip) { [weak self] fraction in
            self?.downloadProgress = fraction
        }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, workDir.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw UpdateError("The downloaded archive could not be unpacked.")
        }
        guard let newApp = try FileManager.default
            .contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else {
            throw UpdateError("The archive contains no app bundle.")
        }

        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        guard let granted = installFolder(for: parent) else {
            throw UpdateError("Without access to “\(parent.lastPathComponent)” the app cannot replace itself.")
        }
        let didStartAccess = granted.startAccessingSecurityScopedResource()
        defer { if didStartAccess { granted.stopAccessingSecurityScopedResource() } }

        // Three careful steps so a failure can NEVER leave "old app gone, new
        // app missing" (that exact half-state once stranded an install):
        // 1. Stage the new bundle INTO the destination folder first — the
        //    write that is most likely to fail happens while the old app is
        //    still in place.
        let staged = parent.appendingPathComponent("BallastViewer.app.update")
        try? FileManager.default.removeItem(at: staged)
        do {
            try FileManager.default.moveItem(at: newApp, to: staged)
        } catch {
            throw UpdateError(
                "Could not write into “\(parent.lastPathComponent)”.\n\(error.localizedDescription)"
            )
        }
        // 2. The running bundle goes to the Trash (macOS keeps the running
        //    code alive via the open files); remember where, for rollback.
        var trashed: NSURL?
        do {
            try FileManager.default.trashItem(at: target, resultingItemURL: &trashed)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw UpdateError(
                "Could not move the current app aside.\n\(error.localizedDescription)"
            )
        }
        // 3. Final same-folder rename; if even that fails, put the old app back.
        do {
            try FileManager.default.moveItem(at: staged, to: target)
        } catch {
            if let trashedURL = trashed as URL? {
                try? FileManager.default.moveItem(at: trashedURL, to: target)
            }
            try? FileManager.default.removeItem(at: staged)
            throw UpdateError(
                "Installing failed — the previous version was put back.\n\(error.localizedDescription)"
            )
        }

        relaunch(target)
    }

    /// Streams the zip to `destination`, reporting progress on the MainActor.
    /// Off the MainActor: this loop moves megabytes.
    nonisolated private static func download(
        from url: URL, to destination: URL,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true else {
            throw NSError(
                domain: "AppUpdater", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "The download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))."]
            )
        }
        let total = response.expectedContentLength
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var written: Int64 = 0
        var lastReported: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                // Report every ~512 KB — enough for a smooth bar, no spam.
                if total > 0, written - lastReported >= 1 << 19 {
                    lastReported = written
                    let fraction = min(1, Double(written) / Double(total))
                    await MainActor.run { progress(fraction) }
                }
            }
        }
        try handle.write(contentsOf: buffer)
        await MainActor.run { progress(1) }
    }

    /// Write access to the folder holding the bundle: directly writable (dev
    /// builds in the build folder), via the stored grant, or by asking once.
    private func installFolder(for parent: URL) -> URL? {
        if FileManager.default.isWritableFile(atPath: parent.path) { return parent }
        if let data = UserDefaults.standard.data(forKey: Self.installFolderBookmarkKey) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data, options: .withSecurityScope,
                relativeTo: nil, bookmarkDataIsStale: &stale
            ), !stale, url.path == parent.path {
                return url
            }
        }
        // The panel is modal: if it opened behind another app the whole app
        // looked frozen and unquittable. Force it to the front.
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Allow Update"
        panel.message = "To install the update, grant access to the folder containing"
            + " BallastViewer (“\(parent.lastPathComponent)”)."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = parent
        guard panel.runModal() == .OK, let url = panel.url, url.path == parent.path else {
            return nil
        }
        if let bookmark = try? url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: Self.installFolderBookmarkKey)
        }
        return url
    }

    private func relaunch(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            // Terminate regardless: the new bundle is in place either way, and
            // quitting runs the normal write-through drain.
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: Dialogs

    private func alert(_ message: String, info: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
    }

    private func confirm(_ message: String, info: String, action: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
