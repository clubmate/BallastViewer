import AppKit
import BallastCore
import GRDB

extension LibraryController {
    // MARK: Add folders

    /// Opens the folder picker for `targetURL` (default: the open library) —
    /// Settings can add folders to ANY known library (U14).
    func presentAddFolderPanel(for targetURL: URL? = nil) {
        guard let target = targetURL ?? libraryURL else { return }
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
        Task { await importFolders(panel.urls, recursive: recursive, into: target) }
    }

    func importFolders(_ urls: [URL], recursive: Bool) async {
        await importFolders(urls, recursive: recursive, into: libraryURL)
    }

    /// Imports into any known library (U14): the open one uses the live pool
    /// (snapshot + events afterwards), a closed one gets a short-lived pool
    /// behind its security scope — managing never requires switching.
    func importFolders(_ urls: [URL], recursive: Bool, into targetURL: URL?) async {
        guard let targetURL else { return }
        // Reentrancy guard: a drop during a running import must not start a
        // second, interleaved `runImport` on the same pool.
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        var added = 0
        var skipped = 0
        if targetURL.path == libraryURL?.path, let library {
            (added, skipped) = await runImport(urls, recursive: recursive, pool: library.pool)
            await refreshSnapshot()
        } else {
            let didStartAccess = targetURL.startAccessingSecurityScopedResource()
            defer { if didStartAccess { targetURL.stopAccessingSecurityScopedResource() } }
            guard let database = try? LibraryDatabase.open(at: targetURL) else {
                errorMessage = "Could not open “\(targetURL.lastPathComponent)” for import."
                return
            }
            (added, skipped) = await runImport(urls, recursive: recursive, pool: database.pool)
            try? database.pool.close()
        }

        let addedText = "Added \(added) photo\(added == 1 ? "" : "s")"
        let skippedText = skipped > 0 ? ", skipped \(skipped) already in the library" : ""
        infoMessage = added > 0 ? "\(addedText)\(skippedText)." : "No new photos found\(skippedText)."
    }

    /// The shared pipeline: register → scan (off-main) → read metadata (bounded
    /// to 12 concurrent file reads, spec §2.4 fix) → one write transaction.
    /// Summary is reported per U2 ("312 added, 40 skipped").
    private func runImport(
        _ urls: [URL], recursive: Bool, pool: DatabasePool
    ) async -> (added: Int, skipped: Int) {
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
                let folder = try await pool.write { db in
                    try ImportDAO.registerFolder(
                        path: folderPath, bookmark: bookmark, recursive: recursive, in: db
                    )
                }
                let files = await Task.detached(priority: .userInitiated) {
                    FolderScanner.scan(url, recursive: recursive)
                }.value
                // Skip metadata reads for files already in the catalog.
                let existing = try await pool.read { db in
                    Set(try String.fetchAll(db, sql: "SELECT path FROM photo"))
                }
                let newFiles = files.filter { !existing.contains($0.path) }
                skipped += files.count - newFiles.count

                let items = await Self.readMetadata(for: newFiles, maxConcurrent: 12)
                let result = try await pool.write { db in
                    try ImportDAO.importPhotos(items, folderId: folder.id!, in: db)
                }
                added += result.added
                skipped += result.skipped
            } catch {
                errorMessage = "Import of “\(url.lastPathComponent)” failed.\n\(error.localizedDescription)"
            }
        }
        return (added, skipped)
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

    // MARK: Managing arbitrary libraries (Settings ▸ Libraries, U14)

    /// Runs work against a CLOSED library's short-lived pool behind its
    /// security scope — off the MainActor: opening a pool and reading are disk
    /// I/O, and a library on a slow or detached network volume must not freeze
    /// the Settings window.
    nonisolated private static func withClosedLibraryPool<T: Sendable>(
        at url: URL, _ body: @escaping @Sendable (DatabasePool) throws -> T
    ) async -> T? {
        await Task.detached(priority: .userInitiated) {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
            guard let database = try? LibraryDatabase.open(at: url) else { return nil as T? }
            defer { try? database.pool.close() }
            return try? body(database.pool)
        }.value
    }

    /// Folder list of any known library, without opening it into the UI.
    func folders(inLibraryAt url: URL) async -> [FolderRecord] {
        if url.path == libraryURL?.path { return snapshot?.folders ?? [] }
        return await Self.withClosedLibraryPool(at: url) { pool in
            try pool.read { try FolderRecord.fetchAll($0) }
        } ?? []
    }

    /// Photo count for the U7 removal confirmation, any library.
    func folderPhotoCount(_ folder: FolderRecord, inLibraryAt url: URL) async -> Int {
        guard let folderId = folder.id else { return 0 }
        if url.path == libraryURL?.path, let library {
            return (try? await library.pool.read { db in
                try ImportDAO.photoCount(inFolder: folderId, db)
            }) ?? 0
        }
        return await Self.withClosedLibraryPool(at: url) { pool in
            try pool.read { try ImportDAO.photoCount(inFolder: folderId, $0) }
        } ?? 0
    }

    /// Removes a folder from any known library. The open library goes through
    /// the regular path (snapshot, events, undo); closed ones write directly.
    func removeFolder(_ folder: FolderRecord, fromLibraryAt url: URL) async {
        if url.path == libraryURL?.path {
            await removeFolder(folder)
            return
        }
        guard let folderId = folder.id else { return }
        _ = await Self.withClosedLibraryPool(at: url) { pool in
            try pool.write { try ImportDAO.removeFolder(folderId, in: $0) }
        }
    }

    /// "Add Existing…": takes a `.ballastlib` from disk (another machine, a
    /// backup) into the known list WITHOUT opening it — validated by a brief
    /// open/close so a broken file fails loudly here, not later in the menu.
    func presentAddExistingLibraryPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add Existing Library"
        panel.allowedContentTypes = [.ballastLibrary]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let database = try LibraryDatabase.open(at: url)
            try? database.pool.close()
        } catch {
            errorMessage = "“\(url.lastPathComponent)” is not a usable library.\n\(error.localizedDescription)"
            return
        }
        addKnownLibrary(url)
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
            // Capture the subtree first so removal is undoable (U8): the folder
            // row, its photos (with ids), and their keyword assignments.
            let captured: (photos: [PhotoRecord], pairs: [(photoId: Int64, keywordId: Int64)]) =
                try await library.pool.read { db in
                    let photos = try PhotoRecord.filter(Column("folderId") == folderId).fetchAll(db)
                    let ids = Set(photos.compactMap(\.id))
                    let pairs = try PhotoDAO.fetchKeywordAssignments(db)
                        .filter { ids.contains($0.photoId) }
                    return (photos, pairs)
                }
            let removed = try await library.pool.write { db in
                try ImportDAO.removeFolder(folderId, in: db)
            }
            registerUndo("Remove Folder") { controller in
                Task {
                    await controller.reinsertFolder(
                        folder, photos: captured.photos, pairs: captured.pairs
                    )
                }
            }
            await refreshSnapshot()
            infoMessage = "Removed the folder and \(removed) photo\(removed == 1 ? "" : "s") from the catalog. Files on disk are untouched."
        } catch {
            errorMessage = "Could not remove the folder.\n\(error.localizedDescription)"
        }
    }

    /// Undo of a folder removal: restores the captured rows verbatim (original
    /// ids included, so batches and assignments stay consistent). Potentially
    /// thousands of rows — the write runs on the pipeline (ordered, off the
    /// MainActor), never as a synchronous transaction.
    private func reinsertFolder(
        _ folder: FolderRecord,
        photos: [PhotoRecord],
        pairs: [(photoId: Int64, keywordId: Int64)]
    ) async {
        guard let pipeline = writePipeline else { return }
        do {
            try await pipeline.submitAndWait { db in
                var folderRecord = folder
                try folderRecord.insert(db)
                for photo in photos {
                    var record = photo
                    try record.insert(db)
                }
                for pair in pairs {
                    try PhotoKeywordRecord(photoId: pair.photoId, keywordId: pair.keywordId)
                        .insert(db, onConflict: .ignore)
                }
            }
        } catch {
            errorMessage = "Could not restore the folder.\n\(error.localizedDescription)"
            return
        }
        registerUndo("Remove Folder") { controller in
            Task { await controller.removeFolder(folder) }
        }
        await refreshSnapshot()
    }
}
