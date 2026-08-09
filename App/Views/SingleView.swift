import AppKit
import BallastCore
import SwiftUI

/// Centre pane in single mode (spec §9.4): the anchor photo scaled to fit,
/// centred; spinner while decoding, warning triangle on failure, "No Photo
/// Selected" without an anchor. Displays the original file at full resolution
/// (U15) — the user's libraries hold modest-sized images, so a display-bucket
/// thumbnail tier is unnecessary.
struct SingleView: View {
    let photo: GridPhoto?
    /// Display-order neighbours of `photo` (previous/next) — prefetched after
    /// the anchor is shown, so stepping hits the originals cache instead of
    /// paying a cold full decode with a spinner per step.
    var neighbors: [GridPhoto] = []
    let pipeline: ThumbnailPipeline

    /// Results carry the path AND orientation they were loaded for: when
    /// stepping quickly, the body renders for the NEW photo while the state
    /// still holds the OLD decode — the old image stays visible (with its own
    /// orientation, never the new photo's) until the new decode lands.
    private enum LoadState {
        case loading
        case loaded(CGImage, path: String, orientation: Int)
        case failed(path: String)
    }

    @State private var state: LoadState = .loading

    var body: some View {
        Group {
            if let photo {
                content(for: photo)
                    .task(id: photo.path) {
                        if let hit = pipeline.cachedOriginal(forPath: photo.path) {
                            state = .loaded(hit.image, path: photo.path, orientation: photo.orientation)
                        } else {
                            let box = await pipeline.originalImage(forPath: photo.path)
                            guard !Task.isCancelled else { return }
                            state = box.map {
                                .loaded($0.image, path: photo.path, orientation: photo.orientation)
                            } ?? .failed(path: photo.path)
                        }
                        // Fire-and-forget neighbour warm-up; the pipeline's
                        // coalescing dedups against a real request when the
                        // user steps onto one of them meanwhile.
                        for neighbor in neighbors where neighbor.path != photo.path {
                            let path = neighbor.path
                            Task { _ = await pipeline.originalImage(forPath: path) }
                        }
                    }
            } else {
                Text("No Photo Selected")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for photo: GridPhoto) -> some View {
        switch state {
        case .loaded(let image, let path, _) where path == photo.path:
            // Decoded unrotated; the stored orientation is applied at the
            // layer level so the rotate action is instant (Q5).
            SingleImageSurface(image: image, orientation: photo.orientation)
        case .loaded(let image, _, let orientation):
            // Stale: the previous photo bridges the gap while the new decode
            // runs — with ITS orientation, so nothing flashes mis-rotated.
            SingleImageSurface(image: image, orientation: orientation)
        case .failed(let path) where path == photo.path:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
        default:
            ProgressView()
        }
    }
}

/// Layer-backed fit-scaled image with the EXIF transform applied on top —
/// same display convention as the grid cells.
private struct SingleImageSurface: NSViewRepresentable {
    let image: CGImage
    let orientation: Int

    func makeNSView(context: Context) -> SingleImageNSView {
        SingleImageNSView()
    }

    func updateNSView(_ view: SingleImageNSView, context: Context) {
        view.display(image: image, orientation: orientation)
    }
}

final class SingleImageNSView: NSView {
    private let imageLayer = CALayer()
    private var transform = OrientationTransform.forEXIF(1)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func display(image: CGImage, orientation: Int) {
        transform = OrientationTransform.forEXIF(orientation)
        withoutAnimation {
            imageLayer.contents = image
            applyLayout()
        }
    }

    override func layout() {
        super.layout()
        withoutAnimation { applyLayout() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// For 90°/270° the layer gets swapped bounds so the aspect-fit happens in
    /// the rotated frame — the rendered footprint then matches the view again.
    private func applyLayout() {
        let size = transform.swapsDimensions
            ? CGSize(width: bounds.height, height: bounds.width)
            : bounds.size
        imageLayer.bounds = CGRect(origin: .zero, size: size)
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)

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
