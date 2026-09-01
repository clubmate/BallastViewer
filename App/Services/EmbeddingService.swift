import BallastCore
import CoreGraphics
import CoreML
import Foundation
import Vision

/// U48: the MobileCLIP encoders behind an actor — `MLModel` is not Sendable,
/// so both models live here and every prediction hops through. Models load
/// lazily on first use and stay loaded.
///
/// Outputs are L2-normalized `[Float]` (512 dims for S2), so cosine similarity
/// downstream is a plain dot product away.
actor EmbeddingService {
    private let imageModelURL: URL
    private let textModelURL: URL
    private var imageModel: MLModel?
    private var textModel: MLModel?
    private let tokenizer: CLIPTokenizer

    struct EncodingError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    init(imageModelURL: URL, textModelURL: URL) throws {
        self.imageModelURL = imageModelURL
        self.textModelURL = textModelURL
        self.tokenizer = try CLIPTokenizer()
    }

    // MARK: Text

    func textEmbedding(_ text: String) throws -> [Float] {
        let model = try loadedTextModel()
        let tokens = tokenizer.encodeFull(text: text)
        let array = try MLMultiArray(shape: [1, NSNumber(value: tokens.count)], dataType: .int32)
        array.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, _ in
            for (index, token) in tokens.enumerated() { buffer[index] = token }
        }
        guard let inputName = model.modelDescription.inputDescriptionsByName.keys.first else {
            throw EncodingError("The text encoder declares no input.")
        }
        let output = try model.prediction(
            from: try MLDictionaryFeatureProvider(dictionary: [inputName: array])
        )
        return EmbeddingMath.l2Normalized(try Self.floats(of: output))
    }

    // MARK: Image

    /// `orientation` is the photo's stored EXIF value — decodes arrive
    /// UNROTATED by design (Q5), and CLIP should not look at sideways images.
    func imageEmbedding(_ box: CGImageBox, orientation: Int) throws -> [Float] {
        let model = try loadedImageModel()
        guard let input = model.modelDescription.inputDescriptionsByName.first(
            where: { $0.value.type == .image }
        ), let constraint = input.value.imageConstraint else {
            throw EncodingError("The image encoder declares no image input.")
        }
        let upright = Self.uprightImage(box.image, orientation: orientation)
        // Center-crop + scale to the model's input size — the same treatment
        // as Apple's demo app, handled by CoreML itself.
        let value = try MLFeatureValue(
            cgImage: upright,
            constraint: constraint,
            options: [.cropAndScale: VNImageCropAndScaleOption.centerCrop.rawValue]
        )
        let output = try model.prediction(
            from: try MLDictionaryFeatureProvider(dictionary: [input.key: value])
        )
        return EmbeddingMath.l2Normalized(try Self.floats(of: output))
    }

    // MARK: Internals

    private func loadedImageModel() throws -> MLModel {
        if let imageModel { return imageModel }
        let model = try MLModel(contentsOf: imageModelURL)
        imageModel = model
        return model
    }

    private func loadedTextModel() throws -> MLModel {
        if let textModel { return textModel }
        let model = try MLModel(contentsOf: textModelURL)
        textModel = model
        return model
    }

    private static func floats(of output: MLFeatureProvider) throws -> [Float] {
        for name in output.featureNames {
            guard let array = output.featureValue(for: name)?.multiArrayValue else { continue }
            var result = [Float](repeating: 0, count: array.count)
            for i in 0 ..< array.count { result[i] = array[i].floatValue }
            return result
        }
        throw EncodingError("The encoder produced no embedding output.")
    }

    /// Bakes the stored orientation into the bitmap. Identity (the common
    /// case) returns the input untouched — this only ever renders the small
    /// 256-px thumbnail, never library pixels.
    private static func uprightImage(_ image: CGImage, orientation: Int) -> CGImage {
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
        // "Rotate clockwise, then mirror" (OrientationTransform convention);
        // in CG coordinates a visual clockwise rotation is a negative angle.
        if transform.mirroredHorizontally {
            context.scaleBy(x: -1, y: 1)
        }
        context.rotate(by: -CGFloat(transform.rotationDegrees) * .pi / 180)
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
