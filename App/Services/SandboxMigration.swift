import Foundation

/// U42: one-time import of the sandboxed builds' state. Sandboxed apps keep
/// their UserDefaults in the container; after the sandbox removal the app
/// reads `~/Library/Preferences` — without this, an updated install would
/// come up looking factory-fresh (no known libraries, no key/MIDI maps).
///
/// Runs before ANY store reads defaults. Only keys the standard domain does
/// not already have are imported, so a re-run (or a mixed old/new launch
/// history) never clobbers newer state. Old security-scoped bookmark blobs
/// migrate as-is — `PortableBookmark.resolve` still reads them.
enum SandboxMigration {
    private static let markerKey = "didMigrateSandboxContainerDefaults"
    /// The updater's folder-grant bookmark — obsolete without a sandbox.
    private static let obsoleteKeys = ["updateInstallFolderBookmark"]

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: markerKey) else { return }
        defaults.set(true, forKey: markerKey)
        let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.bolliboll.ballastviewer/Data/Library/Preferences/com.bolliboll.ballastviewer.plist"
        )
        guard let imported = NSDictionary(contentsOf: plist) as? [String: Any] else { return }
        for (key, value) in imported
        where !obsoleteKeys.contains(key) && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
