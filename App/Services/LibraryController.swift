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
    private(set) var recentLibraries: [URL] = []

    /// Non-nil presents the app-wide error alert. User-initiated failures are
    /// never silent (fixes spec §4.1/§4.2).
    var errorMessage: String?
    /// Non-error notices (import summaries etc.).
    var infoMessage: String?

    // MARK: Import state (used by LibraryController+Import)

    var isImporting = false

    struct PendingFolderRemoval: Identifiable {
        let folder: FolderRecord
        let photoCount: Int
        var id: Int64 { folder.id ?? 0 }
    }
    /// Non-nil presents the folder-removal confirmation (U7).
    var pendingFolderRemoval: PendingFolderRemoval?
    /// Folders dropped while no library was open — imported after creation (U1).
    private var pendingImportFolders: [URL] = []

    private let bookmarks = BookmarkStore()
    /// URL we successfully called startAccessingSecurityScopedResource on.
    private var accessedURL: URL?

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
        recentLibraries = bookmarks.recentURLs()
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

    func clearRecents() {
        bookmarks.clearRecents()
        recentLibraries = []
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
        rebuildPhotoIndex()
        bookmarks.saveLastOpened(url)
        bookmarks.addRecent(url)
        recentLibraries = bookmarks.recentURLs()
        emitCatalogEvent(.catalogReplaced)
    }

    private func releaseCurrent() {
        try? library?.pool.close()
        if let url = accessedURL {
            url.stopAccessingSecurityScopedResource()
            accessedURL = nil
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
