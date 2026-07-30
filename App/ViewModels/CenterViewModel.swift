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
    var showLeftPanel = true
    var showRightPanel = true
    var showBottomPanel = true

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

    /// Bottom-bar search (spec §11.3): ANDs with the active collection, applies
    /// on every keystroke, session-only. Deliberately NOT cleared on collection
    /// switch — the always-visible field + chip keep it visible instead (C6/U5).
    var searchText = "" {
        didSet { if oldValue != searchText { applyFilterChange() } }
    }

    @ObservationIgnored private var randomOrder = StableRandomOrder()
    @ObservationIgnored private var visibleIdSet: Set<Int64> = []
    /// Query caches, refreshed on collection/catalog changes.
    @ObservationIgnored private var collectionsById: [Int64: SmartCollectionRecord] = [:]
    @ObservationIgnored private var rulesByCollection: [Int64: [CollectionRuleRecord]] = [:]
    @ObservationIgnored private var currentLibraryURL: URL?

    init(controller: LibraryController) {
        self.controller = controller
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
            facts: photo.id.map { snapshot.queryFacts(forPhotoId: $0) } ?? PhotoQueryFacts(),
            item: activeItem,
            collectionsById: collectionsById,
            rulesByCollection: rulesByCollection,
            lastImportBatchId: snapshot.meta.lastImportBatchId
        ) else { return false }
        guard !searchText.isEmpty else { return true }
        return SearchFilter.matches(
            filename: photo.filename,
            keywordPaths: photo.id.map { snapshot.queryFacts(forPhotoId: $0).keywordPaths } ?? [],
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
        visiblePhotos = sorted.compactMap { photo in
            photo.id.map { GridPhoto(id: $0, path: photo.path, orientation: photo.orientation) }
        }
        visibleIdSet = Set(visiblePhotos.map(\.id))
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
            } else if isVisible, let record {
                valueUpdates.append(GridPhoto(id: id, path: record.path, orientation: record.orientation))
            }
        }
        guard !(removals.isEmpty && insertions.isEmpty && valueUpdates.isEmpty) else { return }

        let anchor = selection.anchorId
        let anchorRemoved = anchor.map { removals.contains($0) } ?? false
        let previousOrder = anchorRemoved ? visiblePhotos.map(\.id) : []

        if !valueUpdates.isEmpty {
            let indexById = Dictionary(
                uniqueKeysWithValues: visiblePhotos.enumerated().map { ($1.id, $0) }
            )
            for updated in valueUpdates {
                if let index = indexById[updated.id], visiblePhotos[index] != updated {
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
                guard let id = record.id else { continue }
                visiblePhotos.append(GridPhoto(id: id, path: record.path, orientation: record.orientation))
                visibleIdSet.insert(id)
            }
        } else {
            for record in records.sorted(by: { SortEngine.areInIncreasingOrder($0, $1, by: sortOption) }) {
                guard let id = record.id else { continue }
                visiblePhotos.insert(
                    GridPhoto(id: id, path: record.path, orientation: record.orientation),
                    at: insertionIndex(for: record)
                )
                visibleIdSet.insert(id)
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
              let index = visiblePhotos.firstIndex(where: { $0.id == anchor })
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
              let index = visiblePhotos.firstIndex(where: { $0.id == anchor })
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
        selection.anchorId.flatMap { id in visiblePhotos.first { $0.id == id } }
    }

    /// 0-based position of the anchor in the visible order.
    var anchorPosition: Int? {
        selection.anchorId.flatMap { id in visiblePhotos.firstIndex { $0.id == id } }
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
