import AppKit
import BallastCore
import SwiftUI

/// The center grid (spec §9.3): N columns, square cells, the same spacing for
/// gaps and outer padding (Q23), selection scrolls into view.
///
/// Backend is NSCollectionView: the SwiftUI LazyVGrid failed the step-5 perf
/// gate at 50k photos (600 ms selection, 30 s worst-case scrollTo — see
/// docs/PLAN.md step notes). NSCollectionView realizes only visible items and
/// scrolls to any index instantly.
struct PhotoGridView: NSViewRepresentable {
    let photos: [GridPhoto]
    let pipeline: ThumbnailPipeline
    let viewModel: CenterViewModel
    /// Settings ▸ Appearance "Spacing between images" (0–50, Q23).
    var spacing: Double = 12

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = GridFlowLayout()
        collectionView.dataSource = context.coordinator
        collectionView.isSelectable = false  // clicks are handled by the item views
        collectionView.backgroundColors = [.clear]
        collectionView.register(GridViewItem.self, forItemWithIdentifier: GridViewItem.identifier)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = collectionView
        context.coordinator.collectionView = collectionView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Reading viewModel properties here registers Observation dependencies,
        // so SwiftUI re-runs this update on selection/column changes.
        context.coordinator.apply(
            photos: photos,
            columnCount: viewModel.columnCount,
            spacing: spacing,
            selection: viewModel.selection,
            pipeline: pipeline
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource {
        private let viewModel: CenterViewModel
        weak var collectionView: NSCollectionView?

        private var photos: [GridPhoto] = []
        private var orderedIds: [Int64] = []
        private var indexById: [Int64: Int] = [:]
        private var selection = SelectionModel()
        private var pipeline: ThumbnailPipeline?

        init(viewModel: CenterViewModel) {
            self.viewModel = viewModel
        }

        func apply(
            photos newPhotos: [GridPhoto],
            columnCount: Int,
            spacing: Double,
            selection newSelection: SelectionModel,
            pipeline: ThumbnailPipeline
        ) {
            self.pipeline = pipeline

            var needsReload = false
            if newPhotos != photos {
                if newPhotos.map(\.id) == orderedIds {
                    // Same photos, changed values (rotation): update realized
                    // items in place — no reload, no thumbnail churn.
                    photos = newPhotos
                    if let collectionView {
                        for case let item as GridViewItem in collectionView.visibleItems() {
                            if let index = indexById[item.photoId] {
                                item.update(photo: photos[index])
                            }
                        }
                    }
                } else {
                    photos = newPhotos
                    orderedIds = newPhotos.map(\.id)
                    indexById = Dictionary(
                        uniqueKeysWithValues: orderedIds.enumerated().map { ($1, $0) }
                    )
                    needsReload = true
                }
            }

            if let layout = collectionView?.collectionViewLayout as? GridFlowLayout,
               layout.columnCount != columnCount || layout.spacing != spacing {
                layout.columnCount = columnCount
                layout.spacing = spacing
                layout.invalidateLayout()
            }

            let previousSelection = selection
            selection = newSelection
            if needsReload {
                collectionView?.reloadData()
            } else if previousSelection != newSelection {
                refreshVisibleSelection()
            }
            if previousSelection.anchorId != newSelection.anchorId {
                scrollToAnchorIfNeeded()
            }
        }

        private func refreshVisibleSelection() {
            guard let collectionView else { return }
            for case let item as GridViewItem in collectionView.visibleItems() {
                item.setSelected(selection.isSelected(item.photoId))
            }
        }

        /// Spec §9.3: selection changes scroll the selected item into view.
        /// Minimal, non-animated scrolling — culling must never wait for motion.
        private func scrollToAnchorIfNeeded() {
            guard let collectionView,
                  let anchorId = selection.anchorId,
                  let index = indexById[anchorId]
            else { return }
            let indexPath = IndexPath(item: index, section: 0)
            if let frame = collectionView.collectionViewLayout?
                .layoutAttributesForItem(at: indexPath)?.frame,
                collectionView.visibleRect.contains(frame) {
                return
            }
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
        }

        // MARK: NSCollectionViewDataSource

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            photos.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: GridViewItem.identifier, for: indexPath
            ) as! GridViewItem
            let photo = photos[indexPath.item]
            guard let pipeline else { return item }

            let cellPoints = (collectionView.collectionViewLayout as? GridFlowLayout)?
                .itemSize.width ?? 128
            let scale = collectionView.window?.backingScaleFactor ?? 2
            let bucket = ThumbnailBuckets.bucket(forPixelSize: Int(cellPoints * scale))

            item.configure(
                photo: photo,
                bucket: bucket,
                isSelected: selection.isSelected(photo.id),
                pipeline: pipeline
            ) { [weak self] id, modifiers, clickCount in
                self?.viewModel.handleClick(on: id, modifiers: modifiers, clickCount: clickCount)
            }
            return item
        }
    }
}

/// Flow layout that recomputes the square cell size from the current width:
/// cell = (width − (N+1)·spacing) / N, floored at 10 (spec §9.3/Q23).
final class GridFlowLayout: NSCollectionViewFlowLayout {
    var columnCount = 5
    var spacing: CGFloat = 12

    override func prepare() {
        if let width = collectionView?.bounds.width {
            let cell = max(10, (width - spacing * CGFloat(columnCount + 1)) / CGFloat(columnCount))
            itemSize = NSSize(width: cell, height: cell)
            minimumInteritemSpacing = spacing
            minimumLineSpacing = spacing
            sectionInset = NSEdgeInsets(top: spacing, left: spacing, bottom: spacing, right: spacing)
        }
        super.prepare()
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        true
    }
}
