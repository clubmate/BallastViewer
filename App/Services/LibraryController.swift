import AppKit
import BallastCore
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
    /// A metadata sync command is running (used by LibraryController+Sync).
    var isSyncing = false

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

    /// Derived query facts per photo (resolved keyword paths + effective group
    /// ids). Building these walks the keyword tree and joins strings — cached
    /// here because counts rebuilds, collection filters, search and metadata
    /// sync all hammer the same lookups. Invalidated on assignment changes
    /// (per photo) and vocabulary changes (wholesale).
    @ObservationIgnored private var factsCache: [Int64: PhotoQueryFacts] = [:]

    func queryFacts(forPhotoId id: Int64) -> PhotoQueryFacts {
        if let cached = factsCache[id] { return cached }
        let facts = snapshot?.queryFacts(forPhotoId: id) ?? PhotoQueryFacts()
        factsCache[id] = facts
        return facts
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
    func mutatePhotos(ids: [Int64], _ mutate: (inout PhotoRecord) -> Void) -> [PhotoRecord] {
        guard snapshot != nil else { return [] }
        var changed: [PhotoRecord] = []
        for id in ids {
            guard let index = photoIndexById[id] else { continue }
            let before = snapshot!.photos[index]
            mutate(&snapshot!.photos[index])
            if snapshot!.photos[index] != before {
                changed.append(snapshot!.photos[index])
            }
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

    func createLibrary(at url: URL) {
        do {
            // The save panel already asked "Replace?" — honour that answer,
            // but only ever remove something that is a library package.
            if FileManager.default.fileExists(atPath: url.path) {
                guard url.pathExtension == LibraryDatabase.packageExtension else {
                    throw LibraryDatabaseError.alreadyExists(url)
                }
                try FileManager.default.removeItem(at: url)
            }
            let database = try LibraryDatabase.create(at: url)
            try install(database, at: url)
        } catch {
            errorMessage = "Could not create the library.\n\(error.localizedDescription)"
        }
    }

    func openLibrary(at url: URL) {
        do {
            try openThrowing(at: url)
        } catch {
            errorMessage = "Could not open “\(url.lastPathComponent)”.\n\(error.localizedDescription)"
        }
    }

    /// Releases the library and prevents auto-reopen; the recents list stays (spec §4.4).
    func closeLibrary() {
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
        do {
            try openThrowing(at: url)
        } catch {
            // The library moved or broke since last launch: start empty, tell the
            // user once, and stop trying on every launch.
            bookmarks.clearLastOpened()
            errorMessage = "The last library “\(url.lastPathComponent)” could not be reopened.\n\(error.localizedDescription)"
        }
    }

    private func openThrowing(at url: URL) throws {
        // Bookmark-resolved URLs need the security scope started before any file
        // access; for fresh panel URLs the call returns false and access is
        // already implicit.
        let didStartAccess = url.startAccessingSecurityScopedResource()
        do {
            let database = try LibraryDatabase.open(at: url)
            releaseCurrent()
            accessedURL = didStartAccess ? url : nil
            try install(database, at: url)
        } catch {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    private func install(_ database: LibraryDatabase, at url: URL) throws {
        let loaded = try database.pool.read { try LibrarySnapshot.load($0) }
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
            // Drain pending writes, then close — closing under a pending write
            // would surface spurious errors. The captured pool keeps the
            // connection alive until the drain completes.
            let pool = library?.pool
            writePipeline = nil
            Task {
                await pipeline.shutdown()
                try? pool?.close()
            }
        } else {
            try? library?.pool.close()
        }
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
    private func startFolderAccess(for folders: [FolderRecord]) {
        for folder in folders {
            guard let data = folder.bookmark else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data, options: .withSecurityScope,
                relativeTo: nil, bookmarkDataIsStale: &isStale
            ), url.startAccessingSecurityScopedResource() else { continue }
            accessedFolderURLs.append(url)
        }
    }

    /// Reloads the in-memory snapshot after bulk changes (import, folder
    /// removal). Single-photo mutations go through `mutatePhotos` + a
    /// `.photosUpdated` event instead — never through a full reload.
    func refreshSnapshot() {
        guard let library else {
            snapshot = nil
            rebuildPhotoIndex()
            emitCatalogEvent(.catalogReplaced)
            return
        }
        do {
            snapshot = try library.pool.read { try LibrarySnapshot.load($0) }
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
        createLibrary(at: url)

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
            Task { await importFolders(dropped, recursive: true) }
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
        openLibrary(at: url)
    }
}
