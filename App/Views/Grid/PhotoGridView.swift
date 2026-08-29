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
    /// Border colour of selected cells (Settings ▸ Appearance).
    var selectionColor: NSColor = .controlAccentColor
    /// False while single mode covers the grid: the collection view stays
    /// alive (scroll position, realized cells) but must not prefetch, and
    /// selection/scroll sync is deferred until it shows again.
    var isVisible = true

    /// Gap and outer padding in points (Q23: one value for both) — fixed by
    /// design, no longer a preference.
    static let spacing: Double = 10

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = GridFlowLayout()
        collectionView.dataSource = context.coordinator
        collectionView.prefetchDataSource = context.coordinator
        collectionView.isSelectable = false  // clicks are handled by the item views
        collectionView.backgroundColors = [.clear]
        collectionView.register(GridViewItem.self, forItemWithIdentifier: GridViewItem.identifier)

        let scrollView = GridScrollView()
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
            selectionColor: selectionColor,
            selection: viewModel.selection,
            pipeline: pipeline,
            isVisible: isVisible
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewPrefetching {
        private let viewModel: CenterViewModel
        weak var collectionView: NSCollectionView?
        // nonisolated(unsafe): only written once on the main actor; deinit
        // (nonisolated) must be able to unregister it.
        nonisolated(unsafe) var scrollerStyleObserver: NSObjectProtocol?

        deinit {
            if let scrollerStyleObserver {
                NotificationCenter.default.removeObserver(scrollerStyleObserver)
            }
        }

        private var photos: [GridPhoto] = []
        private var orderedIds: [Int64] = []
        private var indexById: [Int64: Int] = [:]
        private var selection = SelectionModel()
        private var selectionColor: NSColor = .controlAccentColor
        private var pipeline: ThumbnailPipeline?
        private var isVisible = true
        /// Selection visuals/scroll skipped while hidden — applied on reveal.
        private var needsVisibleSync = false

        init(viewModel: CenterViewModel) {
            self.viewModel = viewModel
        }

        func apply(
            photos newPhotos: [GridPhoto],
            columnCount: Int,
            selectionColor newSelectionColor: NSColor,
            selection newSelection: SelectionModel,
            pipeline: ThumbnailPipeline,
            isVisible newIsVisible: Bool
        ) {
            self.pipeline = pipeline
            let becameVisible = !isVisible && newIsVisible
            if isVisible && !newIsVisible {
                // Hidden under the single view: in-flight prefetches would
                // decode for cells nobody sees.
                cancelAllPrefetches()
            }
            isVisible = newIsVisible

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
               layout.columnCount != columnCount {
                layout.columnCount = columnCount
                layout.invalidateLayout()
            }

            let colorChanged = selectionColor != newSelectionColor
            selectionColor = newSelectionColor
            let previousSelection = selection
            selection = newSelection
            if needsReload {
                // Membership changed: queued prefetches point at stale index
                // paths — drop them, the new visible set re-requests. The
                // reload itself is not deferred while hidden: the collection
                // view's item count must never lag the data source.
                cancelAllPrefetches()
                collectionView?.reloadData()
            }
            let selectionChanged = previousSelection != newSelection || colorChanged
            let anchorChanged = previousSelection.anchorId != newSelection.anchorId
            guard isVisible else {
                // Every anchor move in single mode would otherwise scroll the
                // hidden grid and realize (decode) cells for nothing.
                if needsReload || selectionChanged || anchorChanged { needsVisibleSync = true }
                return
            }
            if becameVisible && needsVisibleSync {
                needsVisibleSync = false
                refreshVisibleSelection()
                scrollToAnchorIfNeeded()
                return
            }
            if !needsReload && selectionChanged {
                refreshVisibleSelection()
            }
            // After a reload (sort/filter change) the same anchor may sit at a
            // new index, off-screen — the anchor-id guard alone missed that.
            if needsReload || anchorChanged {
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
                item.setSelected(selection.isSelected(item.photoId), color: selectionColor)
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

        // MARK: Prefetching

        /// Thumbnail requests for cells just outside the viewport, so fast
        /// scrolling hits memory instead of showing empty cells until the
        /// disk/decode round trip lands. Cancellation feeds the pipeline's
        /// refcounted in-flight bookkeeping.
        private var prefetchTasks: [IndexPath: Task<Void, Never>] = [:]

        /// Lets a task compare itself against the dictionary entry on
        /// completion (a task cannot reference its own handle directly).
        private final class TaskBox: @unchecked Sendable {
            var value: Task<Void, Never>?
        }

        private func cancelAllPrefetches() {
            for task in prefetchTasks.values { task.cancel() }
            prefetchTasks = [:]
        }

        private func currentBucket(_ collectionView: NSCollectionView) -> Int {
            let cellPoints = (collectionView.collectionViewLayout as? GridFlowLayout)?
                .cellSize ?? 128
            let scale = collectionView.window?.backingScaleFactor ?? 2
            return ThumbnailBuckets.bucket(forPixelSize: Int(cellPoints * scale))
        }

        func collectionView(_ collectionView: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            guard let pipeline, isVisible else { return }
            let bucket = currentBucket(collectionView)
            for indexPath in indexPaths where photos.indices.contains(indexPath.item) {
                let path = photos[indexPath.item].path
                let currentTask = TaskBox()
                guard pipeline.cachedThumbnail(forPath: path, longEdge: bucket) == nil else { continue }
                // Replace, don't stack: a stale task for the same slot would
                // otherwise keep decoding for a cell that moved on.
                prefetchTasks[indexPath]?.cancel()
                let task = Task { [weak self] in
                    _ = await pipeline.thumbnail(forPath: path, longEdge: bucket)
                    // AppKit only cancels prefetches for cells that never
                    // became visible; everything else must remove itself or
                    // the dictionary grows by one dead entry per scrolled cell.
                    guard let self, !Task.isCancelled else { return }
                    if self.prefetchTasks[indexPath] == currentTask.value {
                        self.prefetchTasks[indexPath] = nil
                    }
                }
                currentTask.value = task
                prefetchTasks[indexPath] = task
            }
        }

        func collectionView(
            _ collectionView: NSCollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]
        ) {
            for indexPath in indexPaths {
                prefetchTasks.removeValue(forKey: indexPath)?.cancel()
            }
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
            // The cell is visible now; its prefetch (if any) has done its job.
            prefetchTasks.removeValue(forKey: indexPath)
            guard let pipeline else { return item }

            let bucket = currentBucket(collectionView)

            item.configure(
                photo: photo,
                bucket: bucket,
                isSelected: selection.isSelected(photo.id),
                selectionColor: selectionColor,
                pipeline: pipeline
            ) { [weak self] id, modifiers, clickCount in
                self?.viewModel.handleClick(on: id, modifiers: modifiers, clickCount: clickCount)
            }
            return item
        }
    }
}

/// One-pass size changes (panel toggle, window resize) must recompute the cell
/// size — without this the layout keeps the old itemSize and just rewraps the
/// rows (see GridFlowLayout.prepare). Frame-change notifications proved
/// unreliable for this: the scroll view's fires before tiling resizes the clip
/// (the width guard then compares stale-vs-stale and skips), and a listener on
/// the clip view races the collection view's own bounds-change handling —
/// whether the layout recomputed depended on notification order, so window
/// resizes froze the cell size intermittently. Overriding `setFrameSize` /
/// `layout` instead is deterministic: both run after the clip view has its
/// final width, on every geometry change, with no ordering to race.
/// Width-guarded: a full flow re-prepare is O(photos), and height-only
/// changes (bottom bar toggle) must not pay it.
final class GridScrollView: NSScrollView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateGridIfWidthChanged()
    }

    override func layout() {
        super.layout()
        invalidateGridIfWidthChanged()
    }

    private func invalidateGridIfWidthChanged() {
        guard let collectionView = documentView as? NSCollectionView,
              let layout = collectionView.collectionViewLayout as? GridFlowLayout,
              layout.lastLayoutWidth != contentView.bounds.width
        else { return }
        layout.invalidateLayout()
    }
}

/// Hand-rolled N-column square grid layout: cell = (width − (N+1)·spacing) / N,
/// floored at 10 (spec §9.3/Q23), gaps EXACTLY `spacing` at every width.
///
/// This replaced NSCollectionViewFlowLayout deliberately. The flow layout
/// treats spacing as a minimum and justifies every row across the content
/// width, so any lag between itemSize and the real width shows up as wrong,
/// zoom-dependent gaps — and setting `itemSize` inside `prepare()` triggers
/// its own invalidation mid-pass, which left the visible layout one resize
/// behind. Here the attributes are computed on demand from `cellSize`, so a
/// re-prepare is O(1) and every query reflects the current width; there is no
/// cached row layout to go stale and no justification to stretch the gaps.
final class GridFlowLayout: NSCollectionViewLayout {
    var columnCount = 5
    let spacing = CGFloat(PhotoGridView.spacing)
    /// The viewport width the current layout was prepared for — the guard that
    /// keeps scrolling and height-only changes from re-preparing.
    private(set) var lastLayoutWidth: CGFloat = 0
    /// Square cell side; exposed for the thumbnail bucket choice.
    private(set) var cellSize: CGFloat = 10
    private var itemCount = 0

    override func prepare() {
        // The viewport (clip view) width, NOT the collection view's own bounds:
        // when the pane resizes in one layout pass (panel toggle, window
        // resize), the document view's width lags a pass behind and prepare()
        // would compute a stale cell size.
        let width = collectionView?.enclosingScrollView?.contentView.bounds.width
            ?? collectionView?.bounds.width ?? 0
        lastLayoutWidth = width
        // Floored: sub-point slack at the trailing edge is invisible; cells
        // drawn on fractional pixel boundaries are not.
        cellSize = max(10, ((width - spacing * CGFloat(columnCount + 1)) / CGFloat(columnCount)).rounded(.down))
        itemCount = collectionView.map {
            $0.numberOfSections > 0 ? $0.numberOfItems(inSection: 0) : 0
        } ?? 0
    }

    override var collectionViewContentSize: NSSize {
        guard itemCount > 0 else { return NSSize(width: lastLayoutWidth, height: 0) }
        let rows = (itemCount + columnCount - 1) / columnCount
        return NSSize(
            width: lastLayoutWidth,
            height: spacing + CGFloat(rows) * (cellSize + spacing)
        )
    }

    /// NSCollectionView is flipped: y grows downward from the top-left.
    private func frame(forItem index: Int) -> NSRect {
        let row = index / columnCount
        let column = index % columnCount
        return NSRect(
            x: spacing + CGFloat(column) * (cellSize + spacing),
            y: spacing + CGFloat(row) * (cellSize + spacing),
            width: cellSize,
            height: cellSize
        )
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard itemCount > 0 else { return [] }
        // Row range from the rect — O(visible), never O(photos).
        let rowHeight = cellSize + spacing
        let firstRow = max(0, Int(((rect.minY - spacing) / rowHeight).rounded(.down)))
        let lastRow = max(firstRow, Int((rect.maxY / rowHeight).rounded(.down)))
        let firstItem = firstRow * columnCount
        let lastItem = min(itemCount - 1, (lastRow + 1) * columnCount - 1)
        guard firstItem <= lastItem else { return [] }
        return (firstItem...lastItem).compactMap { index in
            let itemFrame = frame(forItem: index)
            guard itemFrame.intersects(rect) else { return nil }
            let attributes = NSCollectionViewLayoutAttributes(
                forItemWith: IndexPath(item: index, section: 0)
            )
            attributes.frame = itemFrame
            return attributes
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item >= 0, indexPath.item < itemCount else { return nil }
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = frame(forItem: indexPath.item)
        return attributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        // Scrolling changes only the origin; a cell-size change needs a new
        // width. Compare the width prepare() will actually consume (the clip
        // view's), not newBounds — the collection view's own bounds can lag a
        // layout pass behind the pane. Column edits invalidate explicitly in
        // `apply`.
        (collectionView?.enclosingScrollView?.contentView.bounds.width ?? newBounds.width)
            != lastLayoutWidth
    }
}
