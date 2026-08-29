import BallastCore
import Foundation
import Observation

/// State behind the inspector's keyword-tree section (U29): section expansion
/// and height (both persisted app-wide), per-node disclosure (session-only),
/// and the subtree-inclusive photo counts.
///
/// Counts are recomputed event-driven with a dirty flag — never per body pass
/// (a body-pass compute would sweep all photos on every rating keystroke), and
/// not at all while the section is collapsed.
@MainActor @Observable
final class KeywordPanelModel {
    @ObservationIgnored private unowned let controller: LibraryController

    /// Section expansion; default collapsed.
    var isExpanded: Bool {
        didSet {
            guard oldValue != isExpanded else { return }
            UserDefaults.standard.set(isExpanded, forKey: Self.expandedKey)
            if isExpanded { recomputeIfDirty() }
        }
    }
    /// Disclosure state of the tree's nodes (session-only, collapsed roots).
    var expandedNodes: Set<Int64> = []
    /// Disclosure state of the first-level group rows — a separate set:
    /// group ids and keyword ids come from different tables and can collide.
    var expandedGroups: Set<Int64> = []
    /// Section height in points; 0 = unset → 30% of the panel at first expand.
    var sectionHeight: Double {
        didSet {
            guard oldValue != sectionHeight else { return }
            UserDefaults.standard.set(sectionHeight, forKey: Self.heightKey)
        }
    }

    /// Photo counts per keyword id (subtree-inclusive) and per group
    /// (KeywordCounts).
    private(set) var counts = KeywordCounts.Result()
    @ObservationIgnored private var countsDirty = true

    private static let expandedKey = "keywordSectionExpanded"
    private static let heightKey = "keywordSectionHeight"

    init(controller: LibraryController) {
        self.controller = controller
        isExpanded = UserDefaults.standard.bool(forKey: Self.expandedKey)
        sectionHeight = UserDefaults.standard.double(forKey: Self.heightKey)
        controller.addCatalogObserver { [weak self] event in
            self?.handle(event)
        }
        if isExpanded { recomputeIfDirty() }
    }

    func toggleNode(_ id: Int64) {
        if expandedNodes.contains(id) {
            expandedNodes.remove(id)
        } else {
            expandedNodes.insert(id)
        }
    }

    func toggleGroup(_ id: Int64) {
        if expandedGroups.contains(id) {
            expandedGroups.remove(id)
        } else {
            expandedGroups.insert(id)
        }
    }

    private func handle(_ event: CatalogEvent) {
        switch event {
        case .photosUpdated, .catalogReplaced:
            // Keyword assignment/removal and vocabulary deletion both surface
            // here; renames don't change counts (ids are stable).
            countsDirty = true
            if isExpanded { recomputeIfDirty() }
        case .collectionsChanged, .collectionListChanged:
            break
        }
    }

    private func recomputeIfDirty() {
        guard countsDirty else { return }
        countsDirty = false
        guard let snapshot = controller.snapshot else {
            counts = KeywordCounts.Result()
            return
        }
        let newCounts = KeywordCounts.compute(
            keywordIdsByPhoto: snapshot.keywordIdsByPhoto,
            tree: snapshot.keywordTree
        )
        if newCounts != counts { counts = newCounts }
    }
}
