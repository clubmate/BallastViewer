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
        didSet { if oldValue.anchorId != selection.anchorId { updateControlSurface() } }
    }
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

    /// Session-only (Q24). Switching *to* Random re-rolls the stable order (Q2).
    var sortOption: SortOption = .filename {
        didSet {
            guard oldValue != sortOption else { return }
            if sortOption == .random {
                var rng = SystemRandomNumberGenerator()
                randomOrder.reroll(ids: visiblePhotos.map(\.id), using: &rng)
            }
            rebuildVisible()
            selection.prune(keeping: visibleIdSet)
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
    @ObservationIgnored private var visibleIdSet: Set<Int64> = []
    /// id → index into visiblePhotos, maintained alongside it — rebuilding this
    /// per keystroke is an O(50k) tax the 16 ms budget cannot afford.
    @ObservationIgnored private var visibleIndexById: [Int64: Int] = [:]
    /// Query caches, refreshed on collection/catalog changes.
    @ObservationIgnored private var collectionsById: [Int64: SmartCollectionRecord] = [:]
    @ObservationIgnored private var rulesByCollection: [Int64: [CollectionRuleRecord]] = [:]
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

    /// A stored/active collection that no longer exists degrades to ALL PHOTOS.
    private func validated(_ item: SidebarItem?) -> SidebarItem {
        guard let item else { return .allPhotos }
        if case .collection(let id) = item, collectionsById[id] == nil {
            return .allPhotos
        }
        return item
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
                if let anchor = selection.anchorId, visibleIdSet.contains(anchor) {
                    selection.prune(keeping: visibleIdSet)
                } else {
                    // Never leave the user with nothing current (spec §10.4).
                    selection.selectSingle(visiblePhotos.first?.id)
                }
            }
            updateControlSurface()
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
        case .photosUpdated(let ids):
            photosDidChange(ids)
        }
    }

    private func refreshQueryCaches() {
        collectionsById = controller.snapshot?.collectionsById ?? [:]
        rulesByCollection = controller.snapshot?.rulesByCollection ?? [:]
    }

    private func passesFilter(_ photo: PhotoRecord) -> Bool {
        guard let snapshot = controller.snapshot else { return false }
        guard SidebarFilter.matches(
            photo,
            facts: photo.id.map { controller.queryFacts(forPhotoId: $0) } ?? PhotoQueryFacts(),
            item: activeItem,
            collectionsById: collectionsById,
            rulesByCollection: rulesByCollection,
            lastImportBatchId: snapshot.meta.lastImportBatchId
        ) else { return false }
        guard !searchText.isEmpty else { return true }
        return SearchFilter.matches(
            filename: photo.filename,
            keywordPaths: photo.id.map { controller.queryFacts(forPhotoId: $0).keywordPaths } ?? [],
            query: searchText
        )
    }

    /// Full recompute — bulk changes only (library open/import, sort or filter
    /// change). Single-photo mutations go through `photosDidChange`.
    private func rebuildVisible() {
        let records = (controller.snapshot?.photos ?? []).filter(passesFilter)
        if sortOption == .random {
            var rng = SystemRandomNumberGenerator()
            randomOrder.reconcile(with: Set(records.compactMap(\.id)), using: &rng)
        }
        let sorted = SortEngine.sorted(records, by: sortOption, randomOrder: randomOrder.order)
        visiblePhotos = sorted.compactMap(makeGridPhoto)
        visibleIdSet = Set(visiblePhotos.map(\.id))
        rebuildVisibleIndex()
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
            selection.prune(keeping: visibleIdSet)
        }
        updateControlSurface()
    }

    /// Incremental update after in-place photo mutations: O(changed + visible),
    /// never a full refilter of the catalog.
    private func photosDidChange(_ ids: [Int64]) {
        var removals = Set<Int64>()
        var insertions: [PhotoRecord] = []
        var valueUpdates: [GridPhoto] = []
        for id in Set(ids) {
            let record = controller.photo(withId: id)
            let matches = record.map(passesFilter) ?? false
            let isVisible = visibleIdSet.contains(id)
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
            visibleIdSet.subtract(removals)
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
            selection.prune(keeping: visibleIdSet)
        }
        // Rating changes alter the LED state even when the anchor stays put.
        updateControlSurface()
    }

    /// Photos that (re-)entered the filter: sorted insertion for the stable
    /// options, shuffled append for Random (Q2).
    private func insert(_ records: [PhotoRecord]) {
        if sortOption == .random {
            var rng = SystemRandomNumberGenerator()
            let newSet = visibleIdSet.union(records.compactMap(\.id))
            randomOrder.reconcile(with: newSet, using: &rng)
            let position = Dictionary(
                uniqueKeysWithValues: randomOrder.order.enumerated().map { ($1, $0) }
            )
            for record in records.sorted(by: {
                (position[$0.id ?? -1] ?? .max) < (position[$1.id ?? -1] ?? .max)
            }) {
                guard let gridPhoto = makeGridPhoto(record) else { continue }
                visiblePhotos.append(gridPhoto)
                visibleIdSet.insert(gridPhoto.id)
            }
        } else {
            for record in records.sorted(by: { SortEngine.areInIncreasingOrder($0, $1, by: sortOption) }) {
                guard let gridPhoto = makeGridPhoto(record) else { continue }
                visiblePhotos.insert(gridPhoto, at: insertionIndex(for: record))
                visibleIdSet.insert(gridPhoto.id)
            }
        }
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
