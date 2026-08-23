#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// How to display a bitmap that was decoded *without* EXIF transform (Q5:
/// decode unrotated, rotate at render time — that is what makes rotation
/// instant and keeps the thumbnail cache orientation-independent).
///
/// Convention: rotate clockwise by `rotationDegrees`, then flip horizontally
/// if `mirroredHorizontally`. The app only produces 1/6/3/8; mirrored values
/// (2/4/5/7) can arrive from files and are honoured for display.
public struct OrientationTransform: Equatable, Sendable {
    public let rotationDegrees: Int
    public let mirroredHorizontally: Bool

    public var swapsDimensions: Bool {
        rotationDegrees == 90 || rotationDegrees == 270
    }

    #if canImport(CoreGraphics)
    /// The layer transform that displays an unrotated bitmap per this
    /// orientation. CGAffineTransform pre-multiplies: `identity.scaledBy(-1)
    /// .rotated(by:)` applies the rotation to the bitmap FIRST and the mirror
    /// to the rotated result, matching the struct's "rotate, then flip
    /// horizontally" convention. The angle is negated for Core Animation's
    /// counter-clockwise convention. Shared by the grid cells and the single
    /// view so both render the same way.
    public var affineTransform: CGAffineTransform {
        var affine = CGAffineTransform.identity
        if mirroredHorizontally {
            affine = affine.scaledBy(x: -1, y: 1)
        }
        return affine.rotated(by: -CGFloat(rotationDegrees) * .pi / 180)
    }
    #endif

    public static func forEXIF(_ orientation: Int) -> OrientationTransform {
        switch orientation {
        case 2: OrientationTransform(rotationDegrees: 0, mirroredHorizontally: true)
        case 3: OrientationTransform(rotationDegrees: 180, mirroredHorizontally: false)
        case 4: OrientationTransform(rotationDegrees: 180, mirroredHorizontally: true)
        case 5: OrientationTransform(rotationDegrees: 90, mirroredHorizontally: true)
        case 6: OrientationTransform(rotationDegrees: 90, mirroredHorizontally: false)
        case 7: OrientationTransform(rotationDegrees: 270, mirroredHorizontally: true)
        case 8: OrientationTransform(rotationDegrees: 270, mirroredHorizontally: false)
        default: OrientationTransform(rotationDegrees: 0, mirroredHorizontally: false)
        }
    }
}
