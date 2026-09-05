import AppKit
import BallastCore

/// One reusable grid item: transparent while loading (spec §9.3), 3 pt border
/// in the Settings ▸ Appearance selection colour with radius 4 when selected. The bitmap is decoded unrotated and
/// transformed at the layer level (Q5), so rotation never re-decodes.
final class GridViewItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("GridViewItem")

    private(set) var photoId: Int64 = 0
    private var loadTask: Task<Void, Never>?
    private var itemView: GridItemView { view as! GridItemView }

    override func loadView() {
        view = GridItemView()
    }

    func configure(
        photo: GridPhoto,
        bucket: Int,
        isSelected: Bool,
        selectionColor: NSColor,
        pipeline: ThumbnailPipeline,
        dragURLs: @escaping (Int64) -> [URL],
        onClick: @escaping (Int64, NSEvent.ModifierFlags, Int) -> Void
    ) {
        let isSamePhoto = photoId == photo.id
        photoId = photo.id
        itemView.onClick = { modifiers, clickCount in onClick(photo.id, modifiers, clickCount) }
        itemView.dragURLs = { dragURLs(photo.id) }
        itemView.setOrientation(photo.orientation)
        setSelected(isSelected, color: selectionColor)
        loadTask?.cancel()

        // Synchronous memory hit: the cached bitmap lands in the SAME frame
        // the cell is configured — no transparent flash, no actor hop.
        if let hit = pipeline.cachedThumbnail(forPath: photo.path, longEdge: bucket) {
            itemView.setImage(hit.image)
            loadTask = nil
            return
        }
        // Keep the current bitmap when re-configuring for the same photo
        // (reloadData after a membership change): the async cache lookup means
        // clearing here would flash every visible cell transparent.
        if !isSamePhoto {
            itemView.setImage(nil)
        }
        loadTask = Task { [weak self] in
            let box = await pipeline.thumbnail(forPath: photo.path, longEdge: bucket)
            guard !Task.isCancelled, let self, self.photoId == photo.id else { return }
            self.itemView.setImage(box?.image)
        }
    }

    func setSelected(_ selected: Bool, color: NSColor) {
        itemView.setSelectedVisual(selected, color: color)
    }

    /// Value-only refresh for an already-configured item — rotation updates the
    /// layer transform without touching the cached bitmap (Q5).
    func update(photo: GridPhoto) {
        guard photo.id == photoId else { return }
        itemView.setOrientation(photo.orientation)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        itemView.setImage(nil)
    }
}

/// Layer-backed image view: CALayer.contents display is essentially free.
/// Fill-crop is TOP-aligned (Q22) by selecting the square `contentsRect` of
/// the source bitmap that, after the orientation transform, shows the top of
/// the displayed image.
final class GridItemView: NSView, NSDraggingSource {
    var onClick: ((NSEvent.ModifierFlags, Int) -> Void)?
    /// U51: the files a drag from this cell carries — the whole selection when
    /// the cell is part of it, else just this photo (the coordinator decides).
    var dragURLs: (() -> [URL])?

    private(set) var isSelected = false
    /// A plain click on an already-selected cell is NOT applied on mouse-down
    /// (it would collapse a multi-selection before a drag could pick it up);
    /// it fires on mouse-up unless the mouse moved far enough to become a drag.
    private var pendingClick: (NSEvent.ModifierFlags, Int)?
    private var mouseDownLocation = NSPoint.zero

    private let imageLayer = CALayer()
    private var transform = OrientationTransform.forEXIF(1)
    private var imageSize = CGSize.zero

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resize
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setImage(_ image: CGImage?) {
        imageSize = image.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        CATransaction.withoutAnimation {
            imageLayer.contents = image
            applyCrop()
        }
    }

    func setOrientation(_ orientation: Int) {
        transform = OrientationTransform.forEXIF(orientation)
        CATransaction.withoutAnimation {
            applyTransform()
            applyCrop()
        }
    }

    func setSelectedVisual(_ selected: Bool, color: NSColor) {
        isSelected = selected
        CATransaction.withoutAnimation {
            layer?.borderWidth = selected ? 3 : 0
            layer?.borderColor = color.cgColor
            layer?.cornerRadius = selected ? 4 : 0
        }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        CATransaction.withoutAnimation {
            imageLayer.frame = bounds
            applyTransform()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    // MARK: Mouse — click on mouse-down (spec §9.3), drag-out as file copy (U51)

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        pendingClick = nil
        let plain = event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty
        if plain, event.clickCount == 1, isSelected {
            pendingClick = (event.modifierFlags, event.clickCount)
        } else {
            onClick?(event.modifierFlags, event.clickCount)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let (modifiers, clickCount) = pendingClick {
            pendingClick = nil
            onClick?(modifiers, clickCount)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = hypot(
            event.locationInWindow.x - mouseDownLocation.x,
            event.locationInWindow.y - mouseDownLocation.y
        )
        guard delta >= 4, let urls = dragURLs?(), !urls.isEmpty else { return }
        pendingClick = nil
        beginFileDrag(urls: urls, event: event)
    }

    /// Drags the files as `NSURL`s: Finder and other apps COPY them (the
    /// source allows only `.copy`), the originals never move. The drag image
    /// is this cell's thumbnail; further files stack behind it.
    private func beginFileDrag(urls: [URL], event: NSEvent) {
        let image = dragImage()
        let items = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(bounds, contents: image)
            return item
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = .stack
    }

    private func dragImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        guard bounds.width > 0, bounds.height > 0,
              let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return image }
        cacheDisplay(in: bounds, to: rep)
        image.addRepresentation(rep)
        return image
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Nothing inside the app accepts photo drops; outside it is a copy.
        context == .outsideApplication ? .copy : []
    }

    private func applyTransform() {
        imageLayer.setAffineTransform(transform.affineTransform)
    }

    /// Q22: the square source region whose post-transform position is the TOP
    /// of the displayed image (horizontally centred). Layer contents are not
    /// flipped, so the bitmap's top row lives at unit-rect y = 1.
    private func applyCrop() {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let side = min(imageSize.width, imageSize.height)
        let sw = side / imageSize.width
        let sh = side / imageSize.height
        let cx = (1 - sw) / 2
        let cy = (1 - sh) / 2
        let rect: CGRect
        if transform.mirroredHorizontally {
            // Mirrored EXIF orientations (2/4/5/7) are read-only rarities:
            // centre crop is fine.
            rect = CGRect(x: cx, y: cy, width: sw, height: sh)
        } else {
            switch transform.rotationDegrees {
            case 90:  // EXIF 6: the stored left edge is displayed on top
                rect = CGRect(x: 0, y: cy, width: sw, height: sh)
            case 180: // stored bottom is displayed on top
                rect = CGRect(x: cx, y: 0, width: sw, height: sh)
            case 270: // EXIF 8: the stored right edge is displayed on top
                rect = CGRect(x: 1 - sw, y: cy, width: sw, height: sh)
            default:  // upright
                rect = CGRect(x: cx, y: 1 - sh, width: sw, height: sh)
            }
        }
        imageLayer.contentsRect = rect
    }
}
