import AppKit
import BallastCore

extension LibraryController {
    // MARK: Add folders

    func presentAddFolderPanel() {
        guard library != nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Add Folders"
        panel.message = "Choose folders to scan for photos."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        let subfolderToggle = NSButton(checkboxWithTitle: "Include subfolders", target: nil, action: nil)
        subfolderToggle.state = .on
        panel.accessoryView = subfolderToggle
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let recursive = subfolderToggle.state == .on
        Task { await importFolders(panel.urls, recursive: recursive) }
    }

    /// Scans and imports each folder: register → scan (off-main) → read metadata
    /// (bounded to 12 concurrent file reads, spec §2.4 fix) → one write
    /// transaction. Summary is reported per U2 ("312 added, 40 skipped").
    func importFolders(_ urls: [URL], recursive: Bool) async {
        guard let library else { return }
        isImporting = true
        defer { isImporting = false }

        var added = 0
        var skipped = 0
        for url in urls {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try? url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
            )
            do {
                let folderPath = url.path
                let folder = try await library.pool.write { db in
                    try ImportDAO.registerFolder(
                        path: folderPath, bookmark: bookmark, recursive: recursive, in: db
                    )
                }
                let files = await Task.detached(priority: .userInitiated) {
                    FolderScanner.scan(url, recursive: recursive)
                }.value
                // Skip metadata reads for files already in the catalog.
                let existing = try await library.pool.read { db in
                    Set(try String.fetchAll(db, sql: "SELECT path FROM photo"))
                }
                let newFiles = files.filter { !existing.contains($0.path) }
                skipped += files.count - newFiles.count

                let items = await Self.readMetadata(for: newFiles, maxConcurrent: 12)
                let result = try await library.pool.write { db in
                    try ImportDAO.importPhotos(items, folderId: folder.id!, in: db)
                }
                added += result.added
                skipped += result.skipped
            } catch {
                errorMessage = "Import of “\(url.lastPathComponent)” failed.\n\(error.localizedDescription)"
            }
        }

        refreshSnapshot()
        let addedText = "Added \(added) photo\(added == 1 ? "" : "s")"
        let skippedText = skipped > 0 ? ", skipped \(skipped) already in the library" : ""
        infoMessage = added > 0 ? "\(addedText)\(skippedText)." : "No new photos found\(skippedText)."
    }

    nonisolated private static func readMetadata(
        for urls: [URL],
        maxConcurrent: Int
    ) async -> [ImportItem] {
        await withTaskGroup(of: ImportItem.self, returning: [ImportItem].self) { group in
            var results: [ImportItem] = []
            results.reserveCapacity(urls.count)
            var iterator = urls.makeIterator()
            func addNext() {
                guard let url = iterator.next() else { return }
                group.addTask {
                    ImportItem(path: url.path, metadata: MetadataReader.read(from: url))
                }
            }
            for _ in 0..<maxConcurrent { addNext() }
            for await item in group {
                results.append(item)
                addNext()
            }
            return results
        }
    }

    // MARK: Remove folder (U7 confirmation, D4 by-membership)

    func requestRemoveFolder(_ folder: FolderRecord) {
        guard let library, let folderId = folder.id else { return }
        Task {
            let count = (try? await library.pool.read { db in
                try ImportDAO.photoCount(inFolder: folderId, db)
            }) ?? 0
            pendingFolderRemoval = PendingFolderRemoval(folder: folder, photoCount: count)
        }
    }

    func confirmRemoveFolder(_ pending: PendingFolderRemoval) {
        Task { await removeFolder(pending.folder) }
    }

    func removeFolder(_ folder: FolderRecord) async {
        guard let library, let folderId = folder.id else { return }
        do {
            let removed = try await library.pool.write { db in
                try ImportDAO.removeFolder(folderId, in: db)
            }
            refreshSnapshot()
            infoMessage = "Removed the folder and \(removed) photo\(removed == 1 ? "" : "s") from the catalog. Files on disk are untouched."
        } catch {
            errorMessage = "Could not remove the folder.\n\(error.localizedDescription)"
        }
    }
}
