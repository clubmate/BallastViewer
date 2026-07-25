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
