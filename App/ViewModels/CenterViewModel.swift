import AppKit
import BallastCore
import Observation

/// Lightweight value the grid renders — decoupled from PhotoRecord so the
/// view layer never touches DB types directly.
struct GridPhoto: Identifiable, Hashable, Sendable {
    let id: Int64
    let path: String
    let orientation: Int
}

enum ViewMode: Equatable {
    case grid, single

    mutating func toggle() {
        self = self == .grid ? .single : .grid
    }
}

/// State of the centre pane: view mode, sort, the filtered+sorted visible list,
/// selection, panel visibility, and the control-surface broadcast. Consumes
/// `CatalogEvent`s so a single-photo change never recomputes the whole list.
@MainActor @Observable
final class CenterViewModel {
    @ObservationIgnored private unowned let controller: LibraryController

    var viewMode: ViewMode = .grid {
        didSet { if oldValue != viewMode { updateControlSurface() } }
    }
    /// 1–10, default 5 (spec §9.3). Session-only by design (Q24).
    var columnCount = 5
    var selection = SelectionModel() {
        didSet {
            guard oldValue != selection else { return }
            // Flip-guarded so the menu bar (which reads only this) is not
            // re-evaluated on every anchor move at key-repeat rate.
            if (oldValue.anchorId == nil) != (selection.anchorId == nil) {
                hasAnchor = selection.anchorId != nil
            }
            rebuildSelectionSummary()
            if oldValue.anchorId != selection.anchorId {
                updateControlSurface()
                // Leaving a photo writes its pending metadata now, not in 2 s.
                if let left = oldValue.anchorId { controller.fileWriteThrough?.flush(left) }
            }
        }
    }
    /// Stable "is anything selected" for menu enablement — written only when
    /// the answer flips (see `selection.didSet`).
    private(set) var hasAnchor = false
    /// Panel visibility persists across launches (spec §18 UI block).
    var showLeftPanel = true {
        didSet { UserDefaults.standard.set(showLeftPanel, forKey: "showLeftPanel") }
    }
    var showRightPanel = true {
        didSet { UserDefaults.standard.set(showRightPanel, forKey: "showRightPanel") }
    }
    var showBottomPanel = true {
        didSet { UserDefaults.standard.set(showBottomPanel, forKey: "showBottomPanel") }
    }

    /// Filtered + sorted photos, in display order. Maintained incrementally.
    private(set) var visiblePhotos: [GridPhoto] = []
    /// LED-feedback broadcast (spec §13.6); consumed by the MIDI step.
    private(set) var controlSurface = ControlSurfaceState()

    /// Everything the inspector shows about the current selection, computed
    /// ONCE per relevant change (selection, affected photo mutations) instead
    /// of per body pass — a Select-All on 50k photos made every inspector
    /// body walk the whole selection several times.
    struct SelectionSummary: Equatable {
        var count = 0
        var title = "No Selection"
        /// The shared rating, or nil when the selection disagrees (mixed).
        var sharedRating: Int? = nil
        var isMixed = false
        var chips: [KeywordChip] = []
    }
    private(set) var selectionSummary = SelectionSummary()

    /// Session-only (Q24). Switching *to* Random re-rolls the stable order (Q2).
    var sortOption: SortOption = .filename {
        didSet {
            guard oldValue != sortOption else { return }
            if sortOption == .random {
                var rng = SystemRandomNumberGenerator()
                randomOrder.reroll(ids: visiblePhotos.map(\.id), using: &rng)
            }
            rebuildVisible()
            pruneSelection()
            updateControlSurface()
        }
    }

    /// The selected sidebar entry — drives the centre filter. Restored per
    /// library from `libraryMeta` (Q24: survives relaunch, unlike sort/mode).
    private(set) var activeItem: SidebarItem = .allPhotos

    /// Bottom-bar search (spec §11.3): ANDs with the active collection,
    /// session-only. Deliberately NOT cleared on collection switch — the
    /// always-visible field + chip keep it visible instead (C6/U5).
    ///
    /// Typing is debounced 150 ms (small deviation from the spec's
    /// per-keystroke apply): one refilter costs ~200 ms at 50k photos, which
    /// would stutter under every keystroke. Clearing applies immediately so
    /// dismissing the chip feels instant.
    var searchText = "" {
        didSet {
            guard oldValue != searchText else { return }
            searchDebounce?.cancel()
            if searchText.isEmpty {
                applyFilterChange()
            } else {
                searchDebounce = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    self?.applyFilterChange()
                }
            }
        }
    }
    @ObservationIgnored private var searchDebounce: Task<Void, Never>?

    /// Applies a pending debounced search immediately (perf probe, test hooks).
    func applySearchNow() {
        searchDebounce?.cancel()
        searchDebounce = nil
        applyFilterChange()
    }

    @ObservationIgnored private var randomOrder = StableRandomOrder()
    /// id → index into visiblePhotos, maintained alongside it — rebuilding this
    /// per keystroke is an O(50k) tax the 16 ms budget cannot afford. Also
    /// the visible-membership set (`visibleIndexById[id] != nil`).
    @ObservationIgnored private var visibleIndexById: [Int64: Int] = [:]
    /// Query caches, refreshed on collection/catalog changes. Rules are kept
    /// pre-compiled — the filter evaluates every photo against them.
    @ObservationIgnored private var collectionsById: [Int64: SmartCollectionRecord] = [:]
    @ObservationIgnored private var compiledCollections: [Int64: CompiledRules] = [:]
    /// Subtree ids (keyword + descendants) for an active `.keyword` item (U29)
    /// — the per-photo filter tests set intersection instead of walking the
    /// tree. Refreshed at the top of every filter pass; cheap (O(subtree)).
    @ObservationIgnored private var activeKeywordSubtree: Set<Int64> = []
    @ObservationIgnored private var currentLibraryURL: URL?

    init(controller: LibraryController) {
        self.controller = controller
        let defaults = UserDefaults.standard
        showLeftPanel = defaults.object(forKey: "showLeftPanel") as? Bool ?? true
        showRightPanel = defaults.object(forKey: "showRightPanel") as? Bool ?? true
        showBottomPanel = defaults.object(forKey: "showBottomPanel") as? Bool ?? true
        controller.addCatalogObserver { [weak self] event in
            self?.handle(event)
        }
        currentLibraryURL = controller.libraryURL
        refreshQueryCaches()
        activeItem = validated(controller.storedSidebarItem)
        rebuildVisible()
        selection.selectSingle(visiblePhotos.first?.id)
        updateControlSurface()
        rebuildSelectionSummary()
    }

    /// See `SelectionSummary`. Equality-guarded so no-op recomputes never
    /// invalidate the inspector.
    private func rebuildSelectionSummary() {
        var summary = SelectionSummary()
        let ids = Array(selection.selectedIds)
        summary.count = ids.count
        switch ids.count {
        case 0:
            summary.title = "No Selection"
        case 1:
            summary.title = selection.anchorId
                .flatMap { controller.photo(withId: $0)?.filename } ?? "1 Photo Selected"
        case let count:
            summary.title = "\(count) Photos Selected"
        }
        if !ids.isEmpty, let snapshot = controller.snapshot {
            var ratings = Set<Int>()
            for id in ids {
                if let rating = controller.photo(withId: id)?.rating {
                    ratings.insert(rating)
                    if ratings.count > 1 { break }
                }
            }
            summary.sharedRating = ratings.count == 1 ? ratings.first : nil
            summary.isMixed = summary.sharedRating == nil
            let common = KeywordChipBuilder.commonKeywordIds(
                photoIds: ids, keywordIdsByPhoto: snapshot.keywordIdsByPhoto
            )
            summary.chips = KeywordChipBuilder.chips(
                forKeywordIds: common, tree: snapshot.keywordTree, groups: snapshot.keywordGroups
            )
        }
        if summary != selectionSummary {
            selectionSummary = summary
        }
    }

    // MARK: Sidebar selection (spec §10.4: switching auto-selects the first photo)

    func selectSidebarItem(_ item: SidebarItem) {
        guard item != activeItem else { return }
        activeItem = item
        rebuildVisible()
        selection.selectSingle(visiblePhotos.first?.id)
        updateControlSurface()
        controller.setSelectedSidebarItem(item)
    }

    /// U29: inspector keyword-tree click — global keyword filter that replaces
    /// the sidebar selection and discards an active search.
    func filterByKeyword(_ id: Int64) {
        if !searchText.isEmpty { searchText = "" }
        selectSidebarItem(.keyword(id))
    }

    /// A stored/active collection or keyword that no longer exists degrades
    /// to ALL PHOTOS.
    private func validated(_ item: SidebarItem?) -> SidebarItem {
        guard let item else { return .allPhotos }
        if case .collection(let id) = item, collectionsById[id] == nil {
            return .allPhotos
        }
        if case .keyword(let id) = item, controller.snapshot?.keywordTree.node(id) == nil {
            return .allPhotos
        }
        return item
    }

    private func refreshActiveKeywordSubtree() {
        guard case .keyword(let id) = activeItem,
              let tree = controller.snapshot?.keywordTree
        else {
            if !activeKeywordSubtree.isEmpty { activeKeywordSubtree = [] }
            return
        }
        activeKeywordSubtree = Set(tree.descendants(of: id)).union([id])
    }

    // MARK: Catalog events

    private func handle(_ event: CatalogEvent) {
        switch event {
        case .catalogReplaced:
            refreshQueryCaches()
            if currentLibraryURL != controller.libraryURL {
                // A different library: restore its own persisted selection.
                currentLibraryURL = controller.libraryURL
                activeItem = validated(controller.storedSidebarItem)
                rebuildVisible()
                selection.selectSingle(visiblePhotos.first?.id)
            } else {
                // Same library, bulk change (import, folder removal).
                activeItem = validated(activeItem)
                rebuildVisible()
                if let anchor = selection.anchorId, visibleIndexById[anchor] != nil {
                    pruneSelection()
                } else {
                    // Never leave the user with nothing current (spec §10.4).
                    selection.selectSingle(visiblePhotos.first?.id)
                }
            }
            updateControlSurface()
            rebuildSelectionSummary()
        case .collectionsChanged:
            refreshQueryCaches()
            let validatedItem = validated(activeItem)
            if validatedItem != activeItem {
                // The active collection was deleted (spec §7.7).
                selectSidebarItem(validatedItem)
            } else if case .collection = activeItem {
                // Rules of the active collection may have changed: re-apply
                // immediately (spec §7.7 quirk), relocating via Q1.
                applyFilterChange()
            }
        case .collectionListChanged:
            // Cosmetic (rename/reorder): membership unchanged — nothing to
            // refilter, no summary/count implications.
            break
        case .photosUpdated(let ids):
            photosDidChange(ids)
        }
    }

    private func refreshQueryCaches() {
        collectionsById = controller.snapshot?.makeCollectionsById() ?? [:]
        let rulesByCollection = controller.snapshot?.makeRulesByCollection() ?? [:]
        compiledCollections = collectionsById.mapValues { collection in
            CompiledRules(
                rulesByCollection[collection.id ?? -1] ?? [], matchAll: collection.matchAll
            )
        }
    }

    /// `search` is folded once per pass by the caller (nil = search off);
    /// facts (incl. the pre-folded filename) are fetched once per photo and
    /// shared by both filters.
    private func passesFilter(_ photo: PhotoRecord, search: SearchFilter.FoldedQuery?) -> Bool {
        guard let snapshot = controller.snapshot else { return false }
        let facts = controller.queryFacts(for: photo)
        guard SidebarFilter.matches(
            photo,
            facts: facts,
            item: activeItem,
            compiledCollections: compiledCollections,
            lastImportBatchId: snapshot.meta.lastImportBatchId,
            activeKeywordSubtree: activeKeywordSubtree
        ) else { return false }
        guard let search else { return true }
        return search.matches(filename: photo.filename, facts: facts)
    }

    /// Full recompute — bulk changes only (library open/import, sort or filter
    /// change). Single-photo mutations go through `photosDidChange`.
    private func rebuildVisible() {
        refreshActiveKeywordSubtree()
        let search = SearchFilter.FoldedQuery(searchText)
        let records = (controller.snapshot?.photos ?? []).filter { passesFilter($0, search: search) }
        if sortOption == .random {
            var rng = SystemRandomNumberGenerator()
            randomOrder.reconcile(with: Set(records.compactMap(\.id)), using: &rng)
        }
        let sorted = SortEngine.sorted(records, by: sortOption, randomOrder: randomOrder.order)
        visiblePhotos = sorted.compactMap(makeGridPhoto)
        rebuildVisibleIndex()
    }

    /// Drops selected ids that left the visible list — O(selection) against
    /// the index map, which must be current (call after `rebuildVisibleIndex`).
    private func pruneSelection() {
        selection.prune { visibleIndexById[$0] != nil }
    }

    private func rebuildVisibleIndex() {
        visibleIndexById = Dictionary(
            uniqueKeysWithValues: visiblePhotos.enumerated().map { ($1.id, $0) }
        )
    }

    private func makeGridPhoto(_ photo: PhotoRecord) -> GridPhoto? {
        guard let id = photo.id else { return nil }
        return GridPhoto(id: id, path: photo.path, orientation: photo.orientation)
    }

    /// Q1: a filter change relocates the anchor via the neighbour rule instead
    /// of jumping to the top.
    private func applyFilterChange() {
        let previousOrder = visiblePhotos.map(\.id)
        let previousAnchor = selection.anchorId
        rebuildVisible()
        if let anchor = previousAnchor {
            let next = NeighbourRule.nextAnchor(
                for: anchor, previousOrder: previousOrder, newOrder: visiblePhotos.map(\.id)
            )
            selection.selectSingle(next)
        } else {
            pruneSelection()
        }
        updateControlSurface()
    }

    /// Incremental update after in-place photo mutations: O(changed + visible),
    /// never a full refilter of the catalog.
    private func photosDidChange(_ ids: [Int64]) {
        // A keyword edit may have grown/shrunk the active subtree (U29).
        refreshActiveKeywordSubtree()
        var removals = Set<Int64>()
        var insertions: [PhotoRecord] = []
        var valueUpdates: [GridPhoto] = []
        // Folded once per event, not per changed photo.
        let search = SearchFilter.FoldedQuery(searchText)
        for id in Set(ids) {
            let record = controller.photo(withId: id)
            let matches = record.map { passesFilter($0, search: search) } ?? false
            let isVisible = visibleIndexById[id] != nil
            if isVisible && !matches {
                removals.insert(id)
            } else if !isVisible && matches, let record {
                insertions.append(record)
            } else if isVisible, let record, let updated = makeGridPhoto(record) {
                valueUpdates.append(updated)
            }
        }
        guard !(removals.isEmpty && insertions.isEmpty && valueUpdates.isEmpty) else { return }

        let anchor = selection.anchorId
        let anchorRemoved = anchor.map { removals.contains($0) } ?? false
        let previousOrder = anchorRemoved ? visiblePhotos.map(\.id) : []

        if !valueUpdates.isEmpty {
            for updated in valueUpdates {
                if let index = visibleIndexById[updated.id], visiblePhotos[index] != updated {
                    visiblePhotos[index] = updated
                }
            }
        }
        if !removals.isEmpty {
            visiblePhotos.removeAll { removals.contains($0.id) }
        }
        if !insertions.isEmpty {
            insert(insertions)
        }
        if !removals.isEmpty || !insertions.isEmpty {
            rebuildVisibleIndex()
        }

        if anchorRemoved, let anchor {
            let next = NeighbourRule.nextAnchor(
                for: anchor, previousOrder: previousOrder, newOrder: visiblePhotos.map(\.id)
            )
            selection.selectSingle(next)
        } else if !removals.isEmpty {
            pruneSelection()
        }
        // Rating changes alter the LED state even when the anchor stays put.
        updateControlSurface()
        if ids.contains(where: { selection.isSelected($0) }) {
            rebuildSelectionSummary()
        }
    }

    /// Above this, per-item `insert(at:)` (an O(n) memmove each) loses against
    /// one append + full re-sort — 5k re-entries into a 50k list would
    /// otherwise move ~125M elements (e.g. undoing a batch rating while a
    /// rating filter is active).
    private static let bulkInsertThreshold = 64

    /// Photos that (re-)entered the filter: sorted insertion for the stable
    /// options, position-stable insertion for Random (Q2) — a re-entering
    /// photo returns to its place in the standing shuffle, exactly where the
    /// next full rebuild would put it (appending would make it jump there).
    private func insert(_ records: [PhotoRecord]) {
        if sortOption == .random {
            var rng = SystemRandomNumberGenerator()
            // The list itself is the membership truth here: removals of the
            // same event are already applied, the index map is rebuilt after.
            let newSet = Set(visiblePhotos.map(\.id)).union(records.compactMap(\.id))
            randomOrder.reconcile(with: newSet, using: &rng)
            let position = Dictionary(
                uniqueKeysWithValues: randomOrder.order.enumerated().map { ($1, $0) }
            )
            if records.count > Self.bulkInsertThreshold {
                for record in records {
                    guard let gridPhoto = makeGridPhoto(record) else { continue }
                    visiblePhotos.append(gridPhoto)
                }
                visiblePhotos.sort { (position[$0.id] ?? .max) < (position[$1.id] ?? .max) }
                return
            }
            for record in records.sorted(by: {
                (position[$0.id ?? -1] ?? .max) < (position[$1.id ?? -1] ?? .max)
            }) {
                guard let gridPhoto = makeGridPhoto(record) else { continue }
                let index = randomInsertionIndex(for: gridPhoto.id, position: position)
                visiblePhotos.insert(gridPhoto, at: index)
            }
        } else {
            let sortedNew = records.sorted {
                SortEngine.areInIncreasingOrder($0, $1, by: sortOption)
            }
            if sortedNew.count > Self.bulkInsertThreshold {
                mergeSorted(sortedNew)
                return
            }
            for record in sortedNew {
                guard let gridPhoto = makeGridPhoto(record) else { continue }
                visiblePhotos.insert(gridPhoto, at: insertionIndex(for: record))
            }
        }
    }

    /// Linear merge of the (sorted) visible list with a sorted batch — O(n+k)
    /// instead of k single insertions.
    private func mergeSorted(_ sortedNew: [PhotoRecord]) {
        var merged: [GridPhoto] = []
        merged.reserveCapacity(visiblePhotos.count + sortedNew.count)
        var existingIndex = 0
        var newIndex = 0
        while existingIndex < visiblePhotos.count, newIndex < sortedNew.count {
            guard let existingRecord = controller.photo(withId: visiblePhotos[existingIndex].id) else {
                merged.append(visiblePhotos[existingIndex])
                existingIndex += 1
                continue
            }
            if SortEngine.areInIncreasingOrder(sortedNew[newIndex], existingRecord, by: sortOption) {
                if let gridPhoto = makeGridPhoto(sortedNew[newIndex]) {
                    merged.append(gridPhoto)
                }
                newIndex += 1
            } else {
                merged.append(visiblePhotos[existingIndex])
                existingIndex += 1
            }
        }
        merged.append(contentsOf: visiblePhotos[existingIndex...])
        for record in sortedNew[newIndex...] {
            guard let gridPhoto = makeGridPhoto(record) else { continue }
            merged.append(gridPhoto)
        }
        visiblePhotos = merged
    }

    /// Binary search over the visible list, which in Random mode is ordered by
    /// the standing shuffle's positions.
    private func randomInsertionIndex(for id: Int64, position: [Int64: Int]) -> Int {
        let target = position[id] ?? .max
        var low = 0
        var high = visiblePhotos.count
        while low < high {
            let mid = (low + high) / 2
            if (position[visiblePhotos[mid].id] ?? .max) < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private func insertionIndex(for record: PhotoRecord) -> Int {
        var low = 0
        var high = visiblePhotos.count
        while low < high {
            let mid = (low + high) / 2
            if let midRecord = controller.photo(withId: visiblePhotos[mid].id),
               SortEngine.areInIncreasingOrder(midRecord, record, by: sortOption) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    // MARK: Navigation (spec §10.3 — always collapses to a single photo)

    /// Next/previous: ±1 in display order, stops at the ends. With no anchor,
    /// next selects the first photo and previous the last.
    func moveAnchor(by delta: Int) {
        guard !visiblePhotos.isEmpty else { return }
        guard let anchor = selection.anchorId,
              let index = visibleIndexById[anchor]
        else {
            selection.selectSingle(delta > 0 ? visiblePhotos.first?.id : visiblePhotos.last?.id)
            return
        }
        let target = index + delta
        guard visiblePhotos.indices.contains(target) else { return }
        selection.selectSingle(visiblePhotos[target].id)
    }

    /// Move up/down one grid row: ± the column count; out-of-range moves are
    /// ignored (no clamping to the edge).
    func moveAnchorByRow(_ direction: Int) {
        guard let anchor = selection.anchorId,
              let index = visibleIndexById[anchor]
        else { return }
        let target = index + direction * columnCount
        guard visiblePhotos.indices.contains(target) else { return }
        selection.selectSingle(visiblePhotos[target].id)
    }

    // MARK: Mouse (spec §9.3)

    func handleClick(on id: Int64, modifiers: NSEvent.ModifierFlags, clickCount: Int) {
        if modifiers.contains(.command) {
            selection.toggle(id)
        } else if modifiers.contains(.shift) {
            selection.selectRange(to: id, in: visiblePhotos.map(\.id))
        } else {
            selection.selectSingle(id)
            if clickCount >= 2 { viewMode = .single }
        }
    }

    // MARK: Anchor lookups (single view, position indicator)

    var anchorPhoto: GridPhoto? {
        anchorPosition.map { visiblePhotos[$0] }
    }

    /// 0-based position of the anchor in the visible order.
    var anchorPosition: Int? {
        selection.anchorId.flatMap { visibleIndexById[$0] }
    }

    /// Display-order neighbours of the anchor (±1) — the single view warms
    /// their originals so stepping never pays a cold decode.
    var anchorNeighbors: [GridPhoto] {
        guard let position = anchorPosition else { return [] }
        return [position - 1, position + 1].compactMap { index in
            visiblePhotos.indices.contains(index) ? visiblePhotos[index] : nil
        }
    }

    // MARK: Control surface (spec §13.6 triggers: anchor, list, view mode)

    private func updateControlSurface() {
        var state = ControlSurfaceState(isSingleView: viewMode == .single)
        if let anchorId = selection.anchorId,
           let snapshot = controller.snapshot,
           let record = controller.photo(withId: anchorId) {
            state.anchorRating = record.rating
            let keywordIds = snapshot.keywordIdsByPhoto[anchorId] ?? []
            state.anchorKeywords = Set(keywordIds.map { snapshot.keywordTree.path(of: $0) })
        }
        if state != controlSurface {
            controlSurface = state
        }
    }
}
