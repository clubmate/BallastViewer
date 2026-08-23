import AppKit
import BallastCore
import GRDB
import Observation
import UniformTypeIdentifiers

extension UTType {
    static let ballastLibrary = UTType(exportedAs: "com.bolliboll.ballastviewer.library")
}

/// Owner of the open library and its in-memory snapshot. All mutations of
/// library state go through this object on the MainActor (see CLAUDE.md).
@MainActor @Observable
final class LibraryController {
    private(set) var library: LibraryDatabase?
    private(set) var libraryURL: URL?
    private(set) var snapshot: LibrarySnapshot?
    private(set) var thumbnails: ThumbnailPipeline?
    /// Every library the app knows (U14): the Library menu's switcher list,
    /// managed in Settings ▸ Libraries. Most recently opened first.
    private(set) var knownLibraries: [URL] = []

    /// Non-nil presents the app-wide error alert. User-initiated failures are
    /// never silent (fixes spec §4.1/§4.2).
    var errorMessage: String?
    /// Non-error notices (import summaries etc.).
    var infoMessage: String?

    // MARK: Import state (used by LibraryController+Import)

    var isImporting = false
    struct QueuedImport {
        var urls: [URL]
        var recursive: Bool
        var targetURL: URL
    }
    /// Drops/panel requests that arrived while an import was running; the
    /// running import drains them in order when it finishes.
    var queuedImports: [QueuedImport] = []
    /// A metadata sync command is running (used by LibraryController+Sync).
    var isSyncing = false
    /// A bulk transaction (import, metadata sync, folder undo) is replacing
    /// catalog state. The modal shield: MainWindow blocks hit-testing and
    /// ActionDispatcher drops keyboard/MIDI/menu actions while this is set —
    /// a rating pressed mid-transaction would otherwise commit behind it and
    /// leave memory and DB disagreeing without an event.
    var isBusy: Bool { isImporting || isSyncing || isTerminating }
    /// `drainWrites` ran: the pipeline is spent and the process is exiting.
    /// Part of the shield so no late mutation lands on a nil pipeline.
    private(set) var isTerminating = false
    /// Shown by the paths the shield cannot cover (structural writes, library
    /// close/switch) when they are refused mid-transaction.
    static let busyMessage = "The library is busy — try again when the import/sync has finished."

    // MARK: Undo (U8)

    /// The host window's undo manager, injected by MainWindow — using the
    /// window's own manager keeps text fields' undo intact and lets the
    /// standard Edit menu drive photo-mutation undo via the responder chain.
    weak var undoManager: UndoManager?

    /// One call = one undoable step; batch mutations register once with the
    /// whole before-state, so ⌘Z reverts the batch atomically (U8).
    ///
    /// The explicit begin/end pair is inert interactively (nested inside the
    /// per-event group AppKit manages) but is what keeps gestures separate in
    /// headless runs, where TestHooks turns `groupsByEvent` off because no
    /// real events ever close the implicit groups.
    func registerUndo(_ actionName: String, _ handler: @escaping @MainActor (LibraryController) -> Void) {
        guard let undoManager else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { handler(target) }
        }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
    }

    struct PendingFolderRemoval: Identifiable {
        let folder: FolderRecord
        let photoCount: Int
        var id: Int64 { folder.id ?? 0 }
    }
    /// Non-nil presents the folder-removal confirmation (U7).
    var pendingFolderRemoval: PendingFolderRemoval?
    /// Folders dropped while no library was open — imported after creation (U1).
    private var pendingImportFolders: [URL] = []

    /// Serialises async write-through mutations for the open library — see
    /// WritePipeline for why unstructured Tasks are not enough. Internal so
    /// the mutation extensions can submit.
    var writePipeline: WritePipeline?

    /// Called with (old derived path, new derived path) after a keyword rename
    /// — wired by BallastViewerApp so key/MIDI keyword bindings (stored as
    /// path strings) follow the rename instead of going stale.
    var keywordPathRenamed: (@MainActor (String, String) -> Void)?

    /// Derived query facts per photo (resolved keyword paths + effective group
    /// ids + folded filename). Building these walks the keyword tree and
    /// joins/folds strings — cached here because counts rebuilds, collection
    /// filters, search and metadata sync all hammer the same lookups.
    /// Invalidated on assignment changes (per photo) and vocabulary changes
    /// (wholesale); filenames never change, so they need no invalidation.
    @ObservationIgnored private var factsCache: [Int64: PhotoQueryFacts] = [:]

    func queryFacts(for photo: PhotoRecord) -> PhotoQueryFacts {
        guard let id = photo.id else { return PhotoQueryFacts() }
        if let cached = factsCache[id] { return cached }
        let facts = snapshot?.queryFacts(for: photo) ?? PhotoQueryFacts()
        factsCache[id] = facts
        return facts
    }

    func queryFacts(forPhotoId id: Int64) -> PhotoQueryFacts {
        if let cached = factsCache[id] { return cached }
        guard let photo = photo(withId: id) else { return PhotoQueryFacts() }
        return queryFacts(for: photo)
    }

    func invalidateFacts(forPhotoIds ids: [Int64]) {
        for id in ids { factsCache[id] = nil }
    }

    func invalidateAllFacts() {
        factsCache = [:]
    }

    /// Waits until every pending write-through mutation has committed — the
    /// app-termination path (AppDelegate). The pipeline is spent afterwards,
    /// which is fine: the process is about to exit.
    func drainWrites() async {
        isTerminating = true
        guard let pipeline = writePipeline else { return }
        writePipeline = nil
        await pipeline.shutdown()
    }

    private let bookmarks = BookmarkStore()
    /// URL we successfully called startAccessingSecurityScopedResource on.
    private var accessedURL: URL?
    /// Folder URLs with active security scope — photos live outside the library
    /// package, so thumbnails and metadata write-back need the folder bookmarks
    /// started for the whole time the library is open.
    private var accessedFolderURLs: [URL] = []

    // MARK: Catalog events + fast photo lookup

    /// snapshot.photos index by photo id, kept in sync with the snapshot so
    /// single-photo mutations are O(1) (see CLAUDE.md mutation contract).
    private var photoIndexById: [Int64: Int] = [:]
    private var catalogObservers: [(CatalogEvent) -> Void] = []

    /// Observers live as long as the controller (i.e. the app) — there is no
    /// removal; long-lived view models register once at construction.
    func addCatalogObserver(_ observer: @escaping (CatalogEvent) -> Void) {
        catalogObservers.append(observer)
    }

    func emitCatalogEvent(_ event: CatalogEvent) {
        for observer in catalogObservers { observer(event) }
    }

    func photo(withId id: Int64) -> PhotoRecord? {
        photoIndexById[id].map { snapshot!.photos[$0] }
    }

    /// In-place snapshot mutation for extensions (snapshot's setter is
    /// file-private by design — all mutations funnel through the controller).
    func mutateSnapshot(_ body: (inout LibrarySnapshot) -> Void) {
        guard snapshot != nil else { return }
        body(&snapshot!)
    }

    /// In-place mutation of catalog photos: memory first (synchronous, instant
    /// UI), the returned records are what the caller persists asynchronously.
    ///
    /// Mutations run against copies first: writing through `snapshot` fires
    /// Observation regardless of whether anything changed, so a no-op (holding
    /// "5" on an already-5-star photo) would re-render every snapshot reader
    /// at key-repeat rate.
    func mutatePhotos(ids: [Int64], _ mutate: (inout PhotoRecord) -> Void) -> [PhotoRecord] {
        guard let current = snapshot else { return [] }
        var changed: [PhotoRecord] = []
        var updates: [(index: Int, record: PhotoRecord)] = []
        for id in ids {
            guard let index = photoIndexById[id] else { continue }
            var copy = current.photos[index]
            mutate(&copy)
            if copy != current.photos[index] {
                updates.append((index, copy))
                changed.append(copy)
            }
        }
        for update in updates {
            snapshot!.photos[update.index] = update.record
        }
        return changed
    }

    private func rebuildPhotoIndex() {
        guard let snapshot else {
            photoIndexById = [:]
            return
        }
        photoIndexById = Dictionary(
            uniqueKeysWithValues: snapshot.photos.enumerated().compactMap { index, photo in
                photo.id.map { ($0, index) }
            }
        )
    }

    var isLibraryOpen: Bool { library != nil }

    init() {
        knownLibraries = bookmarks.knownURLs()
        reopenLastLibrary()
    }

    // MARK: Lifecycle

    /// Serialises open/create requests: the launch auto-reopen and an explicit
    /// open (menu, TestHooks) may overlap now that opening suspends for the
    /// off-main snapshot load — interleaved installs would corrupt state.
    private let openQueue = TaskQueue()

    func createLibrary(at url: URL) async {
        await openQueue.run {
            guard self.refuseIfBusy() else { return }
            do {
                // Package removal + creation + migration is disk I/O — off
                // the MainActor, mirroring `openThrowing`.
                let database = try await Task.detached(priority: .userInitiated) {
                    // The save panel already asked "Replace?" — honour that
                    // answer, but only ever remove something that is a
                    // library package.
                    if FileManager.default.fileExists(atPath: url.path) {
                        guard url.pathExtension == LibraryDatabase.packageExtension else {
                            throw LibraryDatabaseError.alreadyExists(url)
                        }
                        try FileManager.default.removeItem(at: url)
                    }
                    return try LibraryDatabase.create(at: url)
                }.value
                try await self.openLoaded(database, at: url, didStartAccess: false)
            } catch {
                self.errorMessage = "Could not create the library.\n\(error.localizedDescription)"
            }
        }
    }

    func openLibrary(at url: URL) async {
        await openQueue.run {
            guard self.refuseIfBusy() else { return }
            do {
                try await self.openThrowing(at: url)
            } catch {
                self.errorMessage = "Could not open “\(url.lastPathComponent)”.\n\(error.localizedDescription)"
            }
        }
    }

    /// Releasing or replacing the open library flushes the write lane
    /// synchronously (`releaseCurrent`) — refused mid-transaction, where that
    /// barrier would freeze the main thread. Returns false when refused.
    @discardableResult
    private func refuseIfBusy() -> Bool {
        guard isBusy else { return true }
        errorMessage = Self.busyMessage
        return false
    }

    /// Releases the library and prevents auto-reopen; the recents list stays (spec §4.4).
    func closeLibrary() {
        guard refuseIfBusy() else { return }
        releaseCurrent()
        library = nil
        libraryURL = nil
        snapshot = nil
        thumbnails = nil
        rebuildPhotoIndex()
        bookmarks.clearLastOpened()
        emitCatalogEvent(.catalogReplaced)
    }

    /// Adds a library to the known list without opening it (U14).
    func addKnownLibrary(_ url: URL) {
        bookmarks.addKnown(url)
        knownLibraries = bookmarks.knownURLs()
    }

    /// Deletes a library (Settings ▸ Libraries, after its U7 confirmation):
    /// closes it if open, moves the package to the Trash — recoverable, and
    /// photo files are never inside the package — and drops it from the list.
    func deleteLibrary(at url: URL) {
        if url.path == libraryURL?.path {
            // Never trash a library whose close was refused (busy).
            guard refuseIfBusy() else { return }
            closeLibrary()
        }
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            errorMessage = "Could not move “\(url.lastPathComponent)” to the Trash.\n\(error.localizedDescription)"
        }
        bookmarks.removeKnown(url)
        knownLibraries = bookmarks.knownURLs()
    }

    private func reopenLastLibrary() {
        guard let url = bookmarks.resolveLastOpened() else { return }
        Task {
            await self.openQueue.run {
                do {
                    try await self.openThrowing(at: url)
                } catch {
                    // The library moved or broke since last launch: start empty,
                    // tell the user once, and stop trying on every launch.
                    self.bookmarks.clearLastOpened()
                    self.errorMessage = "The last library “\(url.lastPathComponent)” could not be reopened.\n\(error.localizedDescription)"
                }
            }
        }
    }

    private func openThrowing(at url: URL) async throws {
        // Bookmark-resolved URLs need the security scope started before any file
        // access; for fresh panel URLs the call returns false and access is
        // already implicit.
        let didStartAccess = url.startAccessingSecurityScopedResource()
        do {
            // Pool creation + migration is disk I/O — off the MainActor.
            let database = try await Task.detached(priority: .userInitiated) {
                try LibraryDatabase.open(at: url)
            }.value
            try await openLoaded(database, at: url, didStartAccess: didStartAccess)
        } catch {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    /// Shared tail of open/create: load the new snapshot OFF the MainActor (a
    /// 50k-photo load was a 0.5–1 s beachball when it ran synchronously here),
    /// and only THEN release the old library and install the mirror.
    ///
    /// Load-before-release is what keeps the outgoing library fully live —
    /// writes still persist — until the new one is ready: releasing first left
    /// a zombie catalog during the load (and permanently after a failed one)
    /// whose mutations were applied in memory and silently dropped.
    private func openLoaded(
        _ database: LibraryDatabase, at url: URL, didStartAccess: Bool
    ) async throws {
        // Reopening the SAME library: queued writes must commit before the
        // new snapshot reads, or they would silently overtake it.
        await writePipeline?.flush()
        let loaded: LibrarySnapshot
        do {
            loaded = try await database.pool.read { try LibrarySnapshot.load($0) }
        } catch {
            try? database.pool.close()
            throw error
        }
        releaseCurrent()
        install(database, snapshot: loaded, at: url, didStartAccess: didStartAccess)
    }

    private func install(
        _ database: LibraryDatabase, snapshot loaded: LibrarySnapshot, at url: URL, didStartAccess: Bool
    ) {
        // Scope bookkeeping is set on success only; the failure path in
        // `openThrowing` stops access itself, so it must never be stopped twice.
        accessedURL = didStartAccess ? url : nil
        snapshot = loaded
        thumbnails = ThumbnailPipeline(libraryUUID: loaded.meta.libraryUUID)
        library = database
        libraryURL = url
        writePipeline = WritePipeline(pool: database.pool) { [weak self] message in
            self?.errorMessage = "Could not save changes to the library.\n\(message)"
        }
        invalidateAllFacts()
        rebuildPhotoIndex()
        startFolderAccess(for: loaded.folders)
        bookmarks.saveLastOpened(url)
        bookmarks.addKnown(url)
        knownLibraries = bookmarks.knownURLs()
        emitCatalogEvent(.catalogReplaced)
    }

    private func releaseCurrent() {
        if let pipeline = writePipeline {
            // Drain pending writes BEFORE closing, synchronously: reopening the
            // same library must never load a snapshot that queued writes then
            // silently overtake. The queue holds only single-row updates, so
            // the barrier is bounded and normally instant.
            writePipeline = nil
            pipeline.flushSync()
            Task { await pipeline.shutdown() }
        }
        try? library?.pool.close()
        invalidateAllFacts()
        if let url = accessedURL {
            url.stopAccessingSecurityScopedResource()
            accessedURL = nil
        }
        for url in accessedFolderURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedFolderURLs = []
        undoManager?.removeAllActions(withTarget: self)
    }

    /// Resolves and starts every folder's security-scoped bookmark. Folders
    /// added this session are implicitly accessible via their panel/drop URLs;
    /// this is what restores access after a relaunch.
    ///
    /// Failures are surfaced, not swallowed: a folder whose bookmark no longer
    /// resolves (moved, renamed, volume gone) would otherwise fail diffusely
    /// later — thumbnails blank, metadata write-back erroring per file. Stale
    /// bookmarks are refreshed in place so they keep resolving.
    private func startFolderAccess(for folders: [FolderRecord]) {
        var inaccessible: [String] = []
        for folder in folders {
            guard let data = folder.bookmark else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data, options: .withSecurityScope,
                relativeTo: nil, bookmarkDataIsStale: &isStale
            ), url.startAccessingSecurityScopedResource() else {
                inaccessible.append((folder.path as NSString).lastPathComponent)
                continue
            }
            accessedFolderURLs.append(url)
            if isStale, let folderId = folder.id,
               let fresh = try? url.bookmarkData(
                   options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
               )
            {
                persist { db in
                    try FolderRecord.filter(key: folderId)
                        .updateAll(db, Column("bookmark").set(to: fresh))
                }
            }
        }
        if !inaccessible.isEmpty {
            errorMessage = "No access to \(inaccessible.count) photo folder\(inaccessible.count == 1 ? "" : "s") (moved or renamed?):\n"
                + inaccessible.prefix(8).map { "• " + $0 }.joined(separator: "\n")
                + "\n\nRe-add the folder\(inaccessible.count == 1 ? "" : "s") to restore thumbnails and metadata sync."
        }
    }

    /// Reloads the in-memory snapshot after bulk changes (import, folder
    /// removal). Single-photo mutations go through `mutatePhotos` + a
    /// `.photosUpdated` event instead — never through a full reload.
    ///
    /// Pending write-through jobs are drained first — the DB read replaces the
    /// in-memory authority, so it must not miss a commit that is still queued
    /// (a rating pressed just before an import finishing would visibly revert).
    func refreshSnapshot() async {
        guard let library else {
            snapshot = nil
            rebuildPhotoIndex()
            emitCatalogEvent(.catalogReplaced)
            return
        }
        await writePipeline?.flush()
        do {
            snapshot = try await library.pool.read { try LibrarySnapshot.load($0) }
            invalidateAllFacts()
            rebuildPhotoIndex()
            emitCatalogEvent(.catalogReplaced)
        } catch {
            errorMessage = "Could not reload the library.\n\(error.localizedDescription)"
        }
    }

    /// Called by drop handling when no library is open (U1): remember the
    /// folders, let the user place a new library, then import them.
    func handleDropWithoutLibrary(_ folders: [URL]) {
        pendingImportFolders = folders
        presentNewLibraryPanel()
    }

    // MARK: Panels

    func presentNewLibraryPanel() {
        let panel = NSSavePanel()
        panel.title = "Create New Library"
        panel.message = "Choose where to save the new library."
        panel.allowedContentTypes = [.ballastLibrary]
        panel.nameFieldStringValue = "MyLibrary"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await createLibrary(at: url)

            // U1: a fresh library flows straight into adding photos.
            guard isLibraryOpen else {
                pendingImportFolders = []
                return
            }
            let dropped = pendingImportFolders
            pendingImportFolders = []
            if dropped.isEmpty {
                presentAddFolderPanel()
            } else {
                await importFolders(dropped, recursive: true)
            }
        }
    }

    func presentOpenLibraryPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Library"
        panel.allowedContentTypes = [.ballastLibrary]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await openLibrary(at: url) }
    }
}

/// FIFO chain of MainActor jobs: each `run` waits for everything enqueued
/// before it. Used to serialise library open/create flows.
@MainActor
final class TaskQueue {
    private var tail: Task<Void, Never>?

    nonisolated init() {}

    func run(_ body: @escaping @MainActor () async -> Void) async {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await body()
        }
        tail = task
        await task.value
    }
}
