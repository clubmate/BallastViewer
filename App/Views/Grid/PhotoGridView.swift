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
        // Thin auto-hiding overlay scroller (spec §9.10 look).
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.documentView = collectionView
        context.coordinator.collectionView = collectionView
        // macOS resets scrollerStyle whenever the system's preferred style
        // changes — with scroll bars on "automatic", plugging/unplugging any
        // HID device (composite MIDI controllers count) flips it to legacy,
        // which TAKES LAYOUT SPACE and visibly reflows the grid. Re-assert
        // overlay so the bar never affects cell geometry.
        context.coordinator.scrollerStyleObserver = NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil, queue: .main
        ) { [weak scrollView] _ in
            MainActor.assumeIsolated {
                scrollView?.scrollerStyle = .overlay
            }
        }
        // One-pass size changes (panel toggle, window resize) must recompute
        // the cell size — without this the layout keeps the old itemSize and
        // just rewraps the rows (see GridFlowLayout.prepare).
        scrollView.postsFrameChangedNotifications = true
        context.coordinator.frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: scrollView, queue: .main
        ) { [weak collectionView] _ in
            MainActor.assumeIsolated {
                collectionView?.collectionViewLayout?.invalidateLayout()
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Belt to the notification's braces: AppKit also resets the style when
        // the view lands in a window.
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
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
        // nonisolated(unsafe): only written once on the main actor; deinit
        // (nonisolated) must be able to unregister them.
        nonisolated(unsafe) var scrollerStyleObserver: NSObjectProtocol?
        nonisolated(unsafe) var frameObserver: NSObjectProtocol?

        deinit {
            if let scrollerStyleObserver {
                NotificationCenter.default.removeObserver(scrollerStyleObserver)
            }
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
        }

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

            // Fast path first: comparing ids is a cheap Int64 sweep, while a
            // full GridPhoto array compare walks 50k strings per keystroke —
            // that alone blew the 16 ms budget.
            var needsReload = false
            if sameIds(newPhotos) {
                // Same membership and order; only values can differ. Realized
                // items are few — compare and refresh just those.
                let previous = photos
                photos = newPhotos
                if let collectionView, !previous.isEmpty {
                    for case let item as GridViewItem in collectionView.visibleItems() {
                        if let index = indexById[item.photoId],
                           photos[index] != previous[index] {
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

        private func sameIds(_ newPhotos: [GridPhoto]) -> Bool {
            guard newPhotos.count == orderedIds.count else { return false }
            for index in newPhotos.indices where newPhotos[index].id != orderedIds[index] {
                return false
            }
            return true
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
        // The viewport (clip view) width, NOT the collection view's own bounds:
        // when the pane resizes in one layout pass (panel toggle, window
        // resize), the document view's width lags a pass behind and prepare()
        // would compute stale cell sizes — the flow layout then rewraps rows
        // with the old itemSize and justifies the leftovers into uneven gaps.
        if let width = collectionView?.enclosingScrollView?.contentView.bounds.width
            ?? collectionView?.bounds.width {
            // Floor the cell size: computing it to EXACTLY fill the width sits
            // on a floating-point knife edge where the flow layout sometimes
            // wraps a row early and justifies the leftovers into huge gaps —
            // visible whenever the width shifts by a scroller. Sub-point slack
            // per row is invisible; an early wrap is not.
            let cell = max(10, ((width - spacing * CGFloat(columnCount + 1)) / CGFloat(columnCount)).rounded(.down))
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
