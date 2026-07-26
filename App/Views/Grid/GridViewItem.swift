import AppKit
import BallastCore

/// One reusable grid item: pixels only (Q22), transparent while loading
/// (spec §9.3), 3 pt accent border with radius 4 when selected. The bitmap is
/// decoded unrotated and transformed at the layer level (Q5), so rotation
/// never re-decodes.
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
        photoId = photo.id
        itemView.onClick = { modifiers, clickCount in onClick(photo.id, modifiers, clickCount) }
        itemView.setOrientation(photo.orientation)
        itemView.setImage(nil)
        setSelected(isSelected)

        loadTask?.cancel()
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
/// Fill-crop via contentsGravity (center crop for now — the Q22 top-aligned
/// crop refinement is tracked for the polish step).
final class GridItemView: NSView {
    var onClick: ((NSEvent.ModifierFlags, Int) -> Void)?

    private let imageLayer = CALayer()
    private var transform = OrientationTransform.forEXIF(1)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setImage(_ image: CGImage?) {
        withoutAnimation {
            imageLayer.contents = image
        }
    }

    func setOrientation(_ orientation: Int) {
        transform = OrientationTransform.forEXIF(orientation)
        withoutAnimation { applyTransform() }
    }

    func setSelectedVisual(_ selected: Bool) {
        withoutAnimation {
            layer?.borderWidth = selected ? 3 : 0
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.cornerRadius = selected ? 4 : 0
        }
    }

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

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
