import Foundation

/// Persists security-scoped bookmarks in UserDefaults: the auto-reopened library
/// and the recents list (max 10, most recent first, deduped by path, spec §4.5).
///
/// Recents are stored as raw bookmark blobs and never re-created wholesale —
/// creating a bookmark requires live access to the URL, which we only have for
/// the entry being added.
struct BookmarkStore {
    private let defaults = UserDefaults.standard
    private static let lastOpenedKey = "lastOpenedLibraryBookmark"
    private static let recentsKey = "recentLibraryBookmarks"
    static let maxRecents = 10

    // MARK: Last opened (auto-reopen)

    func saveLastOpened(_ url: URL) {
        guard let data = try? bookmarkData(url) else { return }
        defaults.set(data, forKey: Self.lastOpenedKey)
    }

    func clearLastOpened() {
        defaults.removeObject(forKey: Self.lastOpenedKey)
    }

    func resolveLastOpened() -> URL? {
        defaults.data(forKey: Self.lastOpenedKey).flatMap(resolve)
    }

    // MARK: Recents

    func addRecent(_ url: URL) {
        guard let newEntry = try? bookmarkData(url) else { return }
        var entries = rawRecents()
        entries.removeAll { resolve($0)?.path == url.path }
        entries.insert(newEntry, at: 0)
        defaults.set(Array(entries.prefix(Self.maxRecents)), forKey: Self.recentsKey)
    }

    /// Entries that no longer resolve are dropped silently (spec §4.5).
    func recentURLs() -> [URL] {
        rawRecents().compactMap(resolve)
    }

    func clearRecents() {
        defaults.removeObject(forKey: Self.recentsKey)
    }

    private func rawRecents() -> [Data] {
        defaults.array(forKey: Self.recentsKey) as? [Data] ?? []
    }

    // MARK: Bookmarks

    private func bookmarkData(_ url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolve(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
