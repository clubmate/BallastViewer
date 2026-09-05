import Foundation

/// U53: what a backup copies and where. A backup is a plain copy — every
/// photo file of the library plus a consistent snapshot of `library.sqlite`
/// — laid out FLAT on the destination (user decision 2026-09-05):
///
///     <destination>/BallastViewerBackup/<folder name>/…   one per library folder
///     <destination>/BallastViewerBackup/<Name>.ballastlib  the database snapshot
///
/// Subfolders keep their structure below the folder name. Two library
/// folders sharing a name (`/A/2008`, `/B/2008`) get their parent prepended
/// (`A - 2008`, `B - 2008`) so they never mix. Restoring is "open the
/// `.ballastlib`" — plus Relink Folder… when the originals moved.
public struct BackupPlan: Sendable, Equatable {
    public struct Item: Sendable, Hashable {
        /// Absolute path of the photo file.
        public var sourcePath: String
        /// Path below the backup root, `/`-separated.
        public var relativePath: String

        public init(sourcePath: String, relativePath: String) {
            self.sourcePath = sourcePath
            self.relativePath = relativePath
        }
    }

    public static let rootFolderName = "BallastViewerBackup"

    public var items: [Item]
    /// Folder id → its directory name below the root.
    public var folderNames: [Int64: String]

    public init(items: [Item], folderNames: [Int64: String]) {
        self.items = items
        self.folderNames = folderNames
    }

    /// Items grouped by folder id, in the order of `items`.
    public func items(inFolder folderId: Int64, folders: [FolderRecord]) -> [Item] {
        guard let name = folderNames[folderId] else { return [] }
        let prefix = name + "/"
        return items.filter { $0.relativePath.hasPrefix(prefix) }
    }

    public static func make(folders: [FolderRecord], photos: [PhotoRecord]) -> BackupPlan {
        let names = targetNames(for: folders)
        let pathById = Dictionary(uniqueKeysWithValues: folders.compactMap { folder in
            folder.id.map { ($0, normalized(folder.path)) }
        })
        var items: [Item] = []
        items.reserveCapacity(photos.count)
        for photo in photos {
            guard let name = names[photo.folderId], let folderPath = pathById[photo.folderId] else { continue }
            let prefix = folderPath + "/"
            let below: String
            if photo.path.hasPrefix(prefix) {
                below = String(photo.path.dropFirst(prefix.count))
            } else {
                // Not under its folder (should not happen; defensive): keep
                // the file, flat.
                below = photo.filename
            }
            items.append(Item(sourcePath: photo.path, relativePath: name + "/" + below))
        }
        return BackupPlan(items: items, folderNames: names)
    }

    /// Directory name per folder: the folder's own name, disambiguated with
    /// the parent's name when two folders share one, and numbered when even
    /// that collides. Deterministic (folders sorted by path).
    public static func targetNames(for folders: [FolderRecord]) -> [Int64: String] {
        let sorted = folders.compactMap { folder -> (id: Int64, path: String)? in
            folder.id.map { ($0, normalized(folder.path)) }
        }.sorted { $0.path < $1.path }

        // Whitespace runs collapse to one space and control characters go:
        // the name travels through ssh argv to a remote shell (see
        // RsyncCommand) and must survive that unchanged.
        func sanitized(_ name: String) -> String {
            let cleaned = name.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }
            return String(String.UnicodeScalarView(cleaned))
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        func base(_ path: String) -> String {
            let name = sanitized((path as NSString).lastPathComponent)
            return name.isEmpty ? "Photos" : name
        }
        func withParent(_ path: String) -> String {
            let parent = sanitized(((path as NSString).deletingLastPathComponent as NSString).lastPathComponent)
            return parent.isEmpty ? base(path) : "\(parent) - \(base(path))"
        }

        var counts: [String: Int] = [:]
        for entry in sorted { counts[base(entry.path), default: 0] += 1 }

        var result: [Int64: String] = [:]
        var used: Set<String> = []
        for entry in sorted {
            var name = counts[base(entry.path)] == 1 ? base(entry.path) : withParent(entry.path)
            if used.contains(name) {
                var n = 2
                while used.contains("\(name) (\(n))") { n += 1 }
                name = "\(name) (\(n))"
            }
            used.insert(name)
            result[entry.id] = name
        }
        return result
    }

    /// Trailing slashes off; `/` stays `/`.
    public static func normalized(_ path: String) -> String {
        var p = path
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }
}

/// When the "time for a backup" notice shows (U53).
public enum BackupSchedule {
    public static let defaultIntervalDays = 30

    /// Due when reminders are on (`intervalDays > 0`), the notice is not
    /// snoozed, and the last backup is older than the interval (or there was
    /// none at all).
    public static func isDue(
        lastBackup: Date?, intervalDays: Int, snoozedUntil: Date?, now: Date = Date()
    ) -> Bool {
        guard intervalDays > 0 else { return false }
        if let snoozedUntil, snoozedUntil > now { return false }
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= TimeInterval(intervalDays) * 86_400
    }
}
