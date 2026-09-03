import BallastCore
import CoreGraphics
import Foundation

/// Bakes a photo's stored EXIF orientation into a bitmap. Decodes arrive
/// UNROTATED by design (Q5 — rotation is a view-layer transform), but the
/// model should not look at sideways photos. Identity (the common case)
/// returns the input untouched; this only ever renders the small thumbnail
/// handed to the model, never library pixels.
enum UprightImage {
    static func make(_ image: CGImage, orientation: Int) -> CGImage {
        let transform = OrientationTransform.forEXIF(orientation)
        guard transform != OrientationTransform.forEXIF(1) else { return image }
        let width = image.width
        let height = image.height
        let outWidth = transform.swapsDimensions ? height : width
        let outHeight = transform.swapsDimensions ? width : height
        guard let context = CGContext(
            data: nil,
            width: outWidth,
            height: outHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.translateBy(x: CGFloat(outWidth) / 2, y: CGFloat(outHeight) / 2)
        // The SAME transform the grid cells and the single view apply to the
        // unrotated bitmap — one convention, one place (OrientationTransform).
        context.concatenate(transform.affineTransform)
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(width) / 2, y: -CGFloat(height) / 2,
                width: CGFloat(width), height: CGFloat(height)
            )
        )
        return context.makeImage() ?? image
    }
}
