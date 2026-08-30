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

        let (downloaded, response) = try await URLSession.shared.download(from: release.zipURL)
        guard (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true else {
            throw UpdateError("The download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
        let zip = workDir.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: downloaded, to: zip)

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

        // The running bundle goes to the Trash (macOS keeps the running code
        // alive via the open files), the new one takes its exact place.
        try FileManager.default.trashItem(at: target, resultingItemURL: nil)
        try FileManager.default.moveItem(at: newApp, to: target)

        relaunch(target)
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
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
    }

    private func confirm(_ message: String, info: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
