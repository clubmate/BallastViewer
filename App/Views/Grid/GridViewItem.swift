import AppKit
import BallastCore

/// One reusable grid item: transparent while loading (spec §9.3), 3 pt accent
/// border with radius 4 when selected. The bitmap is decoded unrotated and
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
        pipeline: ThumbnailPipeline,
        onClick: @escaping (Int64, NSEvent.ModifierFlags, Int) -> Void
    ) {
        let isSamePhoto = photoId == photo.id
        photoId = photo.id
        itemView.onClick = { modifiers, clickCount in onClick(photo.id, modifiers, clickCount) }
        itemView.setOrientation(photo.orientation)
        setSelected(isSelected)
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

    func setSelected(_ selected: Bool) {
        itemView.setSelectedVisual(selected)
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
final class GridItemView: NSView {
    var onClick: ((NSEvent.ModifierFlags, Int) -> Void)?

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
        withoutAnimation {
            imageLayer.contents = image
            applyCrop()
        }
    }

    func setOrientation(_ orientation: Int) {
        transform = OrientationTransform.forEXIF(orientation)
        withoutAnimation {
            applyTransform()
            applyCrop()
        }
    }

    func setSelectedVisual(_ selected: Bool) {
        withoutAnimation {
            layer?.borderWidth = selected ? 3 : 0
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.cornerRadius = selected ? 4 : 0
        }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        withoutAnimation {
            imageLayer.frame = bounds
            applyTransform()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(event.modifierFlags, event.clickCount)
    }

    private func applyTransform() {
        var affine = CGAffineTransform.identity
        if transform.mirroredHorizontally {
            affine = affine.scaledBy(x: -1, y: 1)
        }
        affine = affine.rotated(by: -CGFloat(transform.rotationDegrees) * .pi / 180)
        imageLayer.setAffineTransform(affine)
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

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
