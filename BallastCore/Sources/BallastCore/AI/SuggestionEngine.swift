import Foundation

/// One (photo, keyword) assignment candidate.
public struct PhotoKeywordPair: Hashable, Sendable {
    public var photoId: Int64
    public var keywordId: Int64

    public init(photoId: Int64, keywordId: Int64) {
        self.photoId = photoId
        self.keywordId = keywordId
    }
}

/// Everything the engine knows about one AI-enabled keyword (U48). With
/// `exampleCount == 0` scoring is exactly the text-description similarity.
public struct KeywordScoringSpec: Sendable {
    public var keywordId: Int64
    /// One embedding per prompt variant ("a photo of …", L2-normalized). A
    /// keyword covering unrelated looks ("phone user OR red car") describes
    /// each as its own variant — the text score is the BEST variant, because
    /// one embedding of an "or" sentence is a washed-out average of both.
    public var textEmbeddings: [[Float]]
    /// Mean embedding of confirmed example photos, L2-normalized (Stage 4).
    public var prototypeEmbedding: [Float]?
    public var exampleCount: Int
    /// The prototype's similarity to the LIBRARY MEAN image embedding — the
    /// score an average, unrelated photo gets against this prototype. CLIP
    /// image embeddings share a common direction (any two photos sit at
    /// cosine ≈ 0.4), so a raw prototype cosine carries that floor while a
    /// text cosine does not (unrelated ≈ 0.1). Subtracting the baseline puts
    /// "how much MORE like the examples than an average photo" on the text
    /// scale the threshold is calibrated for. Measured 2026-09-02 (12-photo
    /// demo): unrelated photos p50 0.4 / max 0.75 raw, ≈ 0 after subtraction.
    public var prototypeBaseline: Float

    public init(
        keywordId: Int64,
        textEmbeddings: [[Float]],
        prototypeEmbedding: [Float]? = nil,
        exampleCount: Int = 0,
        prototypeBaseline: Float = 0
    ) {
        self.keywordId = keywordId
        self.textEmbeddings = textEmbeddings
        self.prototypeEmbedding = prototypeEmbedding
        self.exampleCount = exampleCount
        self.prototypeBaseline = prototypeBaseline
    }
}

/// Pure scoring core of the AI keywording (U48): photo embeddings × keyword
/// specs → suggestions above threshold. Platform code (CoreML, ImageIO) stays
/// in the app target; this is what the tests pin down.
public enum SuggestionEngine {
    public struct Suggestion: Equatable, Sendable {
        public var pair: PhotoKeywordPair
        public var score: Float
    }

    /// The prototype's weight grows with the number of examples:
    /// `α = k / (k + n)` is the text description's share.
    static func textWeight(exampleCount: Int, k: Float = 8) -> Float {
        k / (k + Float(max(0, exampleCount)))
    }

    /// Stage 4: the L2-normalized mean of the example embeddings — "what this
    /// keyword's confirmed photos look like". Nil when there are no examples
    /// (or they cancel out to a zero vector, which must not produce NaNs).
    public static func prototype(of embeddings: [[Float]]) -> [Float]? {
        guard let first = embeddings.first else { return nil }
        var mean = [Float](repeating: 0, count: first.count)
        for embedding in embeddings where embedding.count == mean.count {
            for i in mean.indices { mean[i] += embedding[i] }
        }
        let normalized = EmbeddingMath.l2Normalized(mean)
        guard normalized.contains(where: { $0 != 0 }) else { return nil }
        return normalized
    }

    /// Splits a stored description into its prompt variants — "|" separates
    /// independent looks of the same keyword. Blank variants are dropped.
    public static func promptVariants(_ description: String) -> [String] {
        description.split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The prototype's baseline for a library: the MEAN cosine an ordinary
    /// photo of the library scores against it, taken over a sample of photo
    /// embeddings (callers leave the keyword's own carriers out of the sample
    /// — they would lift the baseline toward themselves). Not the cosine
    /// against a normalized mean vector: that overstates the floor because the
    /// mean of a cone of unit vectors is shorter than one.
    public static func prototypeBaseline(prototype: [Float], sample: [[Float]]) -> Float {
        guard !sample.isEmpty else { return 0 }
        var sum: Float = 0
        for vector in sample { sum += EmbeddingMath.cosine(prototype, vector) }
        return sum / Float(sample.count)
    }

    /// The photo's prototype similarity RELATIVE to the library: raw cosine
    /// minus the prototype's baseline (≈ 0 for an unrelated photo, clearly
    /// positive for one that looks like the confirmed examples).
    public static func prototypeExcess(photo: [Float], spec: KeywordScoringSpec) -> Float? {
        guard let prototype = spec.prototypeEmbedding, spec.exampleCount > 0 else { return nil }
        return EmbeddingMath.cosine(photo, prototype) - spec.prototypeBaseline
    }

    /// Score of one photo against one keyword spec: best prompt variant,
    /// blended with the library-relative prototype excess when examples exist.
    public static func score(photo: [Float], spec: KeywordScoringSpec) -> Float {
        let textScore = spec.textEmbeddings
            .map { EmbeddingMath.cosine(photo, $0) }
            .max() ?? 0
        guard let excess = prototypeExcess(photo: photo, spec: spec) else {
            return textScore
        }
        let alpha = textWeight(exampleCount: spec.exampleCount)
        return alpha * textScore + (1 - alpha) * excess
    }

    /// All pairs scoring at or above `threshold`, minus `skip` (already
    /// assigned, already pending, or previously rejected). Sorted by score
    /// descending so callers can present or batch the strongest first.
    public static func suggestions(
        photoEmbeddings: [Int64: [Float]],
        specs: [KeywordScoringSpec],
        threshold: Float,
        skip: Set<PhotoKeywordPair> = []
    ) -> [Suggestion] {
        var result: [Suggestion] = []
        for (photoId, embedding) in photoEmbeddings {
            for spec in specs {
                let pair = PhotoKeywordPair(photoId: photoId, keywordId: spec.keywordId)
                guard !skip.contains(pair) else { continue }
                let value = score(photo: embedding, spec: spec)
                if value >= threshold {
                    result.append(Suggestion(pair: pair, score: value))
                }
            }
        }
        return result.sorted { $0.score > $1.score }
    }
}
