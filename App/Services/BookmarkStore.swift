import Foundation

/// U42 (sandbox removed): new bookmarks are PLAIN — they still track moves
/// and renames, which is all we need without a sandbox. Blobs written by the
/// sandboxed builds are security-scoped; resolution tries plain first and
/// falls back to the scoped variant so pre-U42 data keeps working.
enum PortableBookmark {
    static func make(_ url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ data: Data, isStale: inout Bool) -> URL? {
        if let url = try? URL(
            resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale
        ) {
            return url
        }
        return try? URL(
            resolvingBookmarkData: data, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &isStale
        )
    }

    static func resolve(_ data: Data) -> URL? {
        var isStale = false
        return resolve(data, isStale: &isStale)
    }
}

/// Persists bookmarks in UserDefaults: the auto-reopened
/// library and the list of ALL known libraries (U14 — the original's
/// 10-entry recents list became the Library menu's switcher, so it is
/// unbounded and only shrinks when the user removes an entry in Settings).
///
/// Entries are stored as raw bookmark blobs and never re-created wholesale —
/// creating a bookmark requires live access to the URL, which we only have for
/// the entry being added.
struct BookmarkStore {
    private let defaults = UserDefaults.standard
    private static let lastOpenedKey = "lastOpenedLibraryBookmark"
    /// Historic key name — pre-U14 recents carry over as known libraries.
    private static let knownKey = "recentLibraryBookmarks"
    /// Path → display name. A CACHE of `libraryMeta.name` (the authority lives
    /// inside each library.sqlite) so the Library menu and Settings can show
    /// names of closed libraries without opening their pools.
    private static let namesKey = "libraryDisplayNames"

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

    // MARK: Known libraries

    /// Most recently opened first, deduped by path, unbounded.
    func addKnown(_ url: URL) {
        guard let newEntry = try? bookmarkData(url) else { return }
        var entries = rawKnown()
        entries.removeAll { resolve($0)?.path == url.path }
        entries.insert(newEntry, at: 0)
        defaults.set(entries, forKey: Self.knownKey)
    }

    /// Removes the entry from the list only — the library on disk is untouched.
    func removeKnown(_ url: URL) {
        var entries = rawKnown()
        entries.removeAll { resolve($0)?.path == url.path }
        defaults.set(entries, forKey: Self.knownKey)
        setDisplayName(nil, forPath: url.path)
    }

    // MARK: Display names (cache of libraryMeta.name)

    func displayNames() -> [String: String] {
        defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
    }

    func setDisplayName(_ name: String?, forPath path: String) {
        var names = displayNames()
        names[path] = name
        defaults.set(names, forKey: Self.namesKey)
    }

    /// Entries that no longer resolve are dropped silently.
    func knownURLs() -> [URL] {
        rawKnown().compactMap(resolve)
    }

    private func rawKnown() -> [Data] {
        defaults.array(forKey: Self.knownKey) as? [Data] ?? []
    }

    // MARK: Bookmarks

    private func bookmarkData(_ url: URL) throws -> Data {
        try PortableBookmark.make(url)
    }

    private func resolve(_ data: Data) -> URL? {
        PortableBookmark.resolve(data)
    }
}
