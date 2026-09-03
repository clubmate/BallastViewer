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
    /// Embedding of the neutral caption "a photo" — the per-photo floor the
    /// text score is measured FROM. A raw CLIP cosine says how well a caption
    /// describes the whole picture, and that floor differs per photo and per
    /// prompt: a generic prompt like "a photo of a man" reaches only ≈ 0.15
    /// on a clean portrait and ≈ 0.05 on a team photo of eleven men, while
    /// "a photo of text" sits at ≈ 0.11 on photos WITHOUT any text. No single
    /// absolute threshold separates matches from non-matches across prompts
    /// (measured 2026-09-03 on 33 real photos). Subtracting the same photo's
    /// cosine to "a photo" removes the per-photo part: 0 means "fits no
    /// better than a plain photo", and one threshold near 0.02 then holds for
    /// generic and specific prompts alike (portraits of women ≥ +0.023 with
    /// "a woman", dogs/beaches ≤ +0.011 on the same set, an airplane +0.13).
    /// Nil keeps the raw cosine (pinned by tests; the app always sets it).
    public var neutralEmbedding: [Float]?
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
    /// The individual confirmed example embeddings (what the prototype was
    /// averaged from) — the nearest-neighbour side of the rejection veto.
    public var exampleEmbeddings: [[Float]]
    /// Embeddings of photos whose suggestion of this keyword the user
    /// REJECTED. Rejections are near-misses by construction (they scored over
    /// threshold once), so "looks more like something rejected than like
    /// anything accepted" is a strong signal — and burst siblings of a
    /// rejected frame are caught exactly. Deliberately NOT a negative
    /// prototype: rejections have mixed reasons, and if they resemble the
    /// positives a mean vector would cancel the positive signal for everyone.
    public var rejectedEmbeddings: [[Float]]

    public init(
        keywordId: Int64,
        textEmbeddings: [[Float]],
        neutralEmbedding: [Float]? = nil,
        prototypeEmbedding: [Float]? = nil,
        exampleCount: Int = 0,
        prototypeBaseline: Float = 0,
        exampleEmbeddings: [[Float]] = [],
        rejectedEmbeddings: [[Float]] = []
    ) {
        self.keywordId = keywordId
        self.textEmbeddings = textEmbeddings
        self.neutralEmbedding = neutralEmbedding
        self.prototypeEmbedding = prototypeEmbedding
        self.exampleCount = exampleCount
        self.prototypeBaseline = prototypeBaseline
        self.exampleEmbeddings = exampleEmbeddings
        self.rejectedEmbeddings = rejectedEmbeddings
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

    /// The neutral caption every text score is measured against — see
    /// `KeywordScoringSpec.neutralEmbedding`. The app embeds it once per run.
    public static let neutralPrompt = "a photo"

    /// The text side of the score: the best prompt variant's cosine, minus
    /// the photo's cosine to the neutral caption when the spec carries it
    /// (raw otherwise). 0 = "no better than a plain photo".
    public static func textScore(photo: [Float], spec: KeywordScoringSpec) -> Float {
        let best = spec.textEmbeddings
            .map { EmbeddingMath.cosine(photo, $0) }
            .max() ?? 0
        guard let neutral = spec.neutralEmbedding, !spec.textEmbeddings.isEmpty else { return best }
        return best - EmbeddingMath.cosine(photo, neutral)
    }

    /// Brings the prototype excess onto the text-contrast scale before the
    /// blend. Image-image similarity spreads ≈ 10× wider than text-image
    /// contrast: measured 2026-09-03 on 33 real photos, held-out portraits
    /// scored excess +0.41…+0.56 against a prototype of 2–4 sister portraits
    /// where their text contrast was +0.02…+0.05, and non-matches ≤ +0.02
    /// versus ≤ +0.01. Without the factor the prototype term alone would
    /// carry any look-alike far past a threshold of 0.02.
    public static let prototypeExcessScale: Float = 0.1

    /// Score of one photo against one keyword spec: the text score, blended
    /// with the (rescaled) library-relative prototype excess when examples
    /// exist.
    public static func score(photo: [Float], spec: KeywordScoringSpec) -> Float {
        let textScore = textScore(photo: photo, spec: spec)
        guard let excess = prototypeExcess(photo: photo, spec: spec) else {
            return textScore
        }
        let alpha = textWeight(exampleCount: spec.exampleCount)
        return alpha * textScore + (1 - alpha) * excess * prototypeExcessScale
    }

    /// A rejected look-alike must be at least this similar before it can veto
    /// — CLIP image-image cosines: burst siblings / same scene ≈ 0.85–0.95,
    /// same subject elsewhere ≈ 0.6–0.75, unrelated ≈ 0.3–0.5. Below the
    /// floor a lone rejection is simply too far away to say anything.
    public static let rejectionVetoFloor: Float = 0.6

    /// The rejection veto: the photo resembles a rejected photo MORE than it
    /// resembles any confirmed example (nearest neighbour on each side), and
    /// that resemblance is at least `rejectionVetoFloor`. With no examples
    /// only the floor decides. Checked only for candidates already over the
    /// threshold — a full pass over every photo × every example would not be.
    public static func isVetoed(photo: [Float], spec: KeywordScoringSpec) -> Bool {
        guard !spec.rejectedEmbeddings.isEmpty else { return false }
        let nearestRejected = spec.rejectedEmbeddings
            .map { EmbeddingMath.cosine(photo, $0) }.max() ?? 0
        guard nearestRejected >= rejectionVetoFloor else { return false }
        let nearestExample = spec.exampleEmbeddings
            .map { EmbeddingMath.cosine(photo, $0) }.max() ?? 0
        return nearestRejected > nearestExample
    }

    public struct Scored: Sendable {
        /// Pairs at or above threshold that survived the veto, best first.
        public var kept: [Suggestion]
        /// Pairs at or above threshold held back as look-alikes of rejected photos.
        public var vetoed: Int
    }

    /// All pairs scoring at or above `threshold`, minus `skip` (already
    /// assigned, already pending, or previously rejected) and minus the
    /// rejection veto. `kept` is sorted by score descending so callers can
    /// present or batch the strongest first.
    public static func scored(
        photoEmbeddings: [Int64: [Float]],
        specs: [KeywordScoringSpec],
        threshold: Float,
        skip: Set<PhotoKeywordPair> = []
    ) -> Scored {
        var kept: [Suggestion] = []
        var vetoed = 0
        for (photoId, embedding) in photoEmbeddings {
            for spec in specs {
                let pair = PhotoKeywordPair(photoId: photoId, keywordId: spec.keywordId)
                guard !skip.contains(pair) else { continue }
                let value = score(photo: embedding, spec: spec)
                guard value >= threshold else { continue }
                if isVetoed(photo: embedding, spec: spec) {
                    vetoed += 1
                } else {
                    kept.append(Suggestion(pair: pair, score: value))
                }
            }
        }
        return Scored(kept: kept.sorted { $0.score > $1.score }, vetoed: vetoed)
    }

    /// `scored(...).kept` — the pairs to apply.
    public static func suggestions(
        photoEmbeddings: [Int64: [Float]],
        specs: [KeywordScoringSpec],
        threshold: Float,
        skip: Set<PhotoKeywordPair> = []
    ) -> [Suggestion] {
        scored(photoEmbeddings: photoEmbeddings, specs: specs, threshold: threshold, skip: skip).kept
    }
}
