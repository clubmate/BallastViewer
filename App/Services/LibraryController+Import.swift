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
        // second, interleaved `runImport` on the same pool — it is queued and
        // run by the import that is in progress once that one has finished.
        guard !isImporting else {
            queuedImports.append(QueuedImport(urls: urls, recursive: recursive, targetURL: targetURL))
            return
        }
        await performImport(urls, recursive: recursive, into: targetURL)
        while !queuedImports.isEmpty {
            let next = queuedImports.removeFirst()
            await performImport(next.urls, recursive: next.recursive, into: next.targetURL)
        }
    }

    private func performImport(_ urls: [URL], recursive: Bool, into targetURL: URL) async {
        isImporting = true
        defer { isImporting = false }

        var added = 0
        var skipped = 0
        var missing = 0
        if targetURL.path == libraryURL?.path, let library, let pipeline = writePipeline {
            var registered: [FolderRecord] = []
            // Writes ride the pipeline: ordered against queued write-through
            // jobs AND against the per-column meta updates (sidebar selection,
            // collapsed groups), so neither can overtake the batch record.
            (added, skipped, missing) = await runImport(
                urls, recursive: recursive,
                writer: ImportWriter(pool: library.pool, pipeline: pipeline),
                registeredFolders: &registered
            )
            if added > 0 {
                await refreshSnapshot()
            } else {
                // Nothing imported (rescan): a full 50k snapshot reload is
                // waste; just mirror the folder registrations (bookmark /
                // recursive updates, possibly a new empty folder).
                mutateSnapshot { snapshot in
                    for folder in registered {
                        if let index = snapshot.folders.firstIndex(where: { $0.id == folder.id }) {
                            snapshot.folders[index] = folder
                        } else {
                            snapshot.folders.append(folder)
                        }
                    }
                }
            }
        } else {
            let didStartAccess = targetURL.startAccessingSecurityScopedResource()
            defer { if didStartAccess { targetURL.stopAccessingSecurityScopedResource() } }
            // Pool creation + migration is disk I/O — off the MainActor, like
            // every other closed-library access (a sleeping network volume
            // must not beachball the Settings window).
            guard let database = await Self.openDetached(at: targetURL) else {
                errorMessage = "Could not open “\(targetURL.lastPathComponent)” for import."
                return
            }
            var registered: [FolderRecord] = []
            (added, skipped, missing) = await runImport(
                urls, recursive: recursive,
                writer: ImportWriter(pool: database.pool, pipeline: nil),
                registeredFolders: &registered
            )
            try? database.pool.close()
        }

        let addedText = "Added \(added) photo\(added == 1 ? "" : "s")"
        let skippedText = skipped > 0 ? ", skipped \(skipped) already in the library" : ""
        var message = added > 0 ? "\(addedText)\(skippedText)." : "No new photos found\(skippedText)."
        if missing > 0 {
            // Catalog rows whose file is gone from the scanned folder (moved
            // or deleted). Reported, not removed — the rows keep their
            // ratings and keywords for when the files come back.
            message += " \(missing) catalogued photo\(missing == 1 ? " is" : "s are") missing on disk."
        }
        infoMessage = message
    }

    /// Where an import writes: the open library's ordered pipeline, or a
    /// closed library's short-lived pool directly (nothing else writes there).
    private struct ImportWriter {
        let pool: DatabasePool
        let pipeline: WritePipeline?

        func write<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
            if let pipeline { return try await pipeline.submitAndWait(body) }
            return try await pool.write(body)
        }
    }

    /// Opens a library's pool off the MainActor; nil if it is not usable.
    nonisolated private static func openDetached(at url: URL) async -> LibraryDatabase? {
        await Task.detached(priority: .userInitiated) {
            try? LibraryDatabase.open(at: url)
        }.value
    }

    /// The shared pipeline: register → scan (off-main) → read metadata (bounded
    /// to 12 concurrent file reads, spec §2.4 fix) → one write transaction.
    /// Summary is reported per U2 ("312 added, 40 skipped").
    private func runImport(
        _ urls: [URL], recursive: Bool, writer: ImportWriter,
        registeredFolders: inout [FolderRecord]
    ) async -> (added: Int, skipped: Int, missing: Int) {
        var added = 0
        var skipped = 0
        var missing = 0
        for url in urls {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try? PortableBookmark.make(url)
            do {
                let folderPath = url.path
                let folder = try await writer.write { db in
                    try ImportDAO.registerFolder(
                        path: folderPath, bookmark: bookmark, recursive: recursive, in: db
                    )
                }
                registeredFolders.append(folder)
                let files = await Task.detached(priority: .userInitiated) {
                    FolderScanner.scan(url, recursive: recursive)
                }.value
                // Skip metadata reads for files already in the catalog; the
                // same set feeds importPhotos, which no longer re-reads it.
                // (Queued writes are committed: registerFolder went through
                // the same ordered lane just before this read.)
                let folderId = folder.id!
                let (existing, inFolder) = try await writer.pool.read { db in
                    (
                        Set(try String.fetchAll(db, sql: "SELECT path FROM photo")),
                        try String.fetchAll(
                            db, sql: "SELECT path FROM photo WHERE folderId = ?", arguments: [folderId]
                        )
                    )
                }
                let scanned = Set(files.map(\.path))
                let newFiles = files.filter { !existing.contains($0.path) }
                skipped += files.count - newFiles.count
                // Only paths inside the scanned scope can be judged missing:
                // after a recursive → non-recursive rescan, photos in
                // subfolders were simply not looked at, not lost on disk.
                missing += inFolder.lazy.filter { path in
                    !scanned.contains(path)
                        && (recursive || (path as NSString).deletingLastPathComponent == folderPath)
                }.count

                let items = await Self.readMetadata(for: newFiles, maxConcurrent: 12)
                let result = try await writer.write { db in
                    try ImportDAO.importPhotos(
                        items, folderId: folderId, existingPaths: existing, in: db
                    )
                }
                added += result.added
                skipped += result.skipped
            } catch {
                errorMessage = "Import of “\(url.lastPathComponent)” failed.\n\(error.localizedDescription)"
            }
        }
        return (added, skipped, missing)
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

    /// Sets the display name of any known library (Settings ▸ Libraries).
    /// A blank name clears back to the package filename. The open library
    /// writes through the pipeline (snapshot first); closed ones write
    /// directly into their meta row. Both update the UserDefaults name cache
    /// so the Library menu and window title follow immediately.
    func setLibraryName(_ rawName: String, forLibraryAt url: URL) async {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String? = trimmed.isEmpty ? nil : trimmed
        if url.path == libraryURL?.path {
            mutateSnapshot { $0.meta.name = name }
            persistMeta(column: "name", value: name)
        } else {
            let saved = await Self.withClosedLibraryPool(at: url) { pool in
                try pool.write { db in
                    try LibraryMetaRecord.filter(key: 1)
                        .updateAll(db, Column("name").set(to: name))
                }
            }
            guard saved != nil else {
                errorMessage = "Could not rename “\(url.lastPathComponent)” — the library could not be opened."
                return
            }
        }
        updateNameCache(name, forPath: url.path)
    }

    /// Whether `url` is catalogued by the open library: a registered folder
    /// itself, or a descendant of a recursive one. Read-only; used by the
    /// BallastPicker guard (U16) — the picker moves files, which would break
    /// the catalog's paths.
    func isFolderInOpenLibrary(_ url: URL) -> Bool {
        guard let folders = snapshot?.folders, !folders.isEmpty else { return false }
        let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        for folder in folders {
            let registered = URL(fileURLWithPath: folder.path, isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath().pathComponents
            if registered == components { return true }
            if folder.recursive, components.count > registered.count,
               Array(components.prefix(registered.count)) == registered {
                return true
            }
        }
        return false
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

    /// U53 "Relink Folder…" (Settings ▸ Libraries): the folder's files now
    /// live at `newURL` (a restored backup, a renamed disk). Rewrites the
    /// folder record and every photo path's prefix — ids, ratings, keywords
    /// and orientation stay. The open library reloads its snapshot
    /// afterwards (paths are everywhere: facts, thumbnails, the AI cache).
    func relinkFolder(_ folder: FolderRecord, to newURL: URL, inLibraryAt url: URL) async {
        guard let folderId = folder.id else { return }
        let newPath = BackupPlan.normalized(newURL.path)
        let oldPath = BackupPlan.normalized(folder.path)
        let bookmark = try? PortableBookmark.make(newURL)
        if url.path == libraryURL?.path {
            guard let pipeline = writePipeline, let snapshot else { return }
            // Validation (review finding): the wrong directory would mark
            // every photo missing. At least one of the folder's photos must
            // exist under the new path (first 200 checked), and the photo
            // paths must actually carry the old prefix (a Unicode
            // normalisation mismatch would otherwise relink 0 photos).
            let photos = snapshot.photos.filter { $0.folderId == folderId }
            if !photos.isEmpty {
                let prefix = oldPath + "/"
                let sample = photos.prefix(200)
                let prefixed = sample.filter { $0.path.hasPrefix(prefix) }
                guard !prefixed.isEmpty else {
                    errorMessage = "Could not relink “\(folder.path)”: its photo paths do not start with the folder path."
                    return
                }
                let found = prefixed.contains { photo in
                    let below = photo.path.dropFirst(prefix.count)
                    return FileManager.default.fileExists(atPath: newPath + "/" + below)
                }
                guard found else {
                    errorMessage = "No photos of “\(folder.path)” were found in “\(newPath)”. Choose the folder that contains the same files."
                    return
                }
            }
            do {
                let changed = try await pipeline.submitAndWait { db in
                    try ImportDAO.relinkFolder(folderId, to: newPath, bookmark: bookmark, in: db)
                }
                await refreshSnapshot()
                // Undo relinks back; that call registers the redo in turn.
                if let relinked = self.snapshot?.folders.first(where: { $0.id == folderId }) {
                    let oldURL = URL(fileURLWithPath: oldPath, isDirectory: true)
                    registerUndo("Relink Folder") { controller in
                        Task { await controller.relinkFolder(relinked, to: oldURL, inLibraryAt: url) }
                    }
                }
                infoMessage = "Relinked “\(folder.path)” to “\(newPath)” — \(changed) photo\(changed == 1 ? "" : "s") updated."
            } catch {
                errorMessage = "Could not relink the folder.\n\(error.localizedDescription)"
            }
        } else {
            let changed = await Self.withClosedLibraryPool(at: url) { pool in
                try pool.write { try ImportDAO.relinkFolder(folderId, to: newPath, bookmark: bookmark, in: $0) }
            }
            if let changed {
                infoMessage = "Relinked “\(folder.path)” to “\(newPath)” — \(changed) photo\(changed == 1 ? "" : "s") updated."
            } else {
                errorMessage = "Could not relink the folder."
            }
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
        Task {
            // Validation open runs off the MainActor (disk I/O, possibly a
            // slow volume); the error is surfaced here, not later in the menu.
            // The same brief open reads the stored display name so the menu
            // and Settings show it right away.
            let validation: Result<String?, any Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let database = try LibraryDatabase.open(at: url)
                    defer { try? database.pool.close() }
                    let name = try? database.pool.read { db in
                        try LibraryMetaRecord.fetchOne(db)?.name
                    }
                    return .success(name ?? nil)
                } catch {
                    return .failure(error)
                }
            }.value
            switch validation {
            case .failure(let error):
                errorMessage = "“\(url.lastPathComponent)” is not a usable library.\n\(error.localizedDescription)"
            case .success(let name):
                addKnownLibrary(url)
                updateNameCache(name, forPath: url.path)
            }
        }
    }

    // MARK: Remove folder (U7 confirmation, D4 by-membership)

    func removeFolder(_ folder: FolderRecord, registerInverse: Bool = true) async {
        guard let folderId = folder.id, let pipeline = writePipeline else { return }
        // Same modal shield as `reinsertFolder`: a rating pressed between the
        // capture and the snapshot reload would be lost on undo (it would
        // commit after the capture, then vanish with the delete).
        let wasBulkUpdating = isBulkUpdating
        isBulkUpdating = true
        defer { isBulkUpdating = wasBulkUpdating }
        struct Removal: Sendable {
            var photos: [PhotoRecord]
            var pairs: [PhotoKeywordRecord]
            var rejected: [RejectedSuggestionRecord]
            var removed: Int
        }
        do {
            // Capture the subtree so removal is undoable (U8): the folder row,
            // its photos (with ids), and their keyword assignments — in the
            // SAME transaction as the delete, on the write pipeline: a rating
            // queued just before must be in the captured rows, a queued
            // assignment insert must commit before (not after, into a deleted
            // photo) the removal, and nothing can slip in between capture and
            // delete.
            let result = try await pipeline.submitAndWait { db -> Removal in
                let photos = try PhotoRecord.filter(Column("folderId") == folderId).fetchAll(db)
                // Restricted in SQL: the full join table can hold
                // hundreds of thousands of pairs for other folders. The rows
                // are captured WITH their U48 status — an undo must bring a
                // pending suggestion back as pending, never as a confirmed
                // (file-facing) keyword — and with the rejection memory the
                // FK cascade would otherwise forget.
                let inFolder = " WHERE photoId IN (SELECT id FROM photo WHERE folderId = ?)"
                let pairs = try PhotoKeywordRecord.fetchAll(
                    db, sql: "SELECT photoId, keywordId, status FROM photoKeyword" + inFolder,
                    arguments: [folderId]
                )
                let rejected = try RejectedSuggestionRecord.fetchAll(
                    db, sql: "SELECT photoId, keywordId FROM rejectedSuggestion" + inFolder,
                    arguments: [folderId]
                )
                let removed = try ImportDAO.removeFolder(folderId, in: db)
                return Removal(photos: photos, pairs: pairs, rejected: rejected, removed: removed)
            }
            if registerInverse {
                registerRemoveFolderUndo(
                    folder, photos: result.photos, pairs: result.pairs, rejected: result.rejected
                )
            }
            await refreshSnapshot()
            let removed = result.removed
            infoMessage = "Removed the folder and \(removed) photo\(removed == 1 ? "" : "s") from the catalog. Files on disk are untouched."
        } catch {
            errorMessage = "Could not remove the folder.\n\(error.localizedDescription)"
        }
    }

    /// Undo of a removal (reinsert) and undo of that undo (remove again) are
    /// registered synchronously inside each other's handler — while the undo
    /// manager is in `isUndoing`/`isRedoing`, which is what routes the inverse
    /// to the redo stack. Registering from the async applier after an `await`
    /// broke redo (the inverse landed on the undo stack instead).
    private func registerRemoveFolderUndo(
        _ folder: FolderRecord, photos: [PhotoRecord],
        pairs: [PhotoKeywordRecord], rejected: [RejectedSuggestionRecord]
    ) {
        registerUndo("Remove Folder") { controller in
            controller.registerReinsertFolderUndo(folder, photos: photos, pairs: pairs, rejected: rejected)
            Task { await controller.reinsertFolder(folder, photos: photos, pairs: pairs, rejected: rejected) }
        }
    }

    private func registerReinsertFolderUndo(
        _ folder: FolderRecord, photos: [PhotoRecord],
        pairs: [PhotoKeywordRecord], rejected: [RejectedSuggestionRecord]
    ) {
        registerUndo("Remove Folder") { controller in
            controller.registerRemoveFolderUndo(folder, photos: photos, pairs: pairs, rejected: rejected)
            Task { await controller.removeFolder(folder, registerInverse: false) }
        }
    }

    /// Undo of a folder removal: restores the captured rows verbatim (original
    /// ids included, so batches and assignments stay consistent). Potentially
    /// thousands of rows — the write runs on the pipeline (ordered, off the
    /// MainActor), never as a synchronous transaction.
    private func reinsertFolder(
        _ folder: FolderRecord,
        photos: [PhotoRecord],
        pairs: [PhotoKeywordRecord],
        rejected: [RejectedSuggestionRecord]
    ) async {
        guard let pipeline = writePipeline else { return }
        // The bulk transaction sits in the write lane: raise the modal shield
        // so a structural edit right after the undo cannot flushSync-block the
        // main thread behind thousands of INSERTs.
        let wasBulkUpdating = isBulkUpdating
        isBulkUpdating = true
        defer { isBulkUpdating = wasBulkUpdating }
        do {
            try await pipeline.submitAndWait { db in
                var folderRecord = folder
                try folderRecord.insert(db)
                for photo in photos {
                    var record = photo
                    try record.insert(db)
                }
                // Status travels with the row (U48): pending comes back pending.
                for pair in pairs {
                    try pair.insert(db, onConflict: .ignore)
                }
                for tombstone in rejected {
                    try tombstone.insert(db, onConflict: .ignore)
                }
            }
        } catch {
            errorMessage = "Could not restore the folder.\n\(error.localizedDescription)"
            return
        }
        await refreshSnapshot()
    }
}
