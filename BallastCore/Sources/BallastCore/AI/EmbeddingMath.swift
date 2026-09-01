import Foundation

/// Vector helpers for CLIP embeddings (U48). 512 dimensions in practice —
/// plain loops are plenty fast for our volumes.
public enum EmbeddingMath {
    /// The vector scaled to unit length. A zero vector comes back unchanged
    /// (a degenerate embedding must not turn into NaNs downstream).
    public static func l2Normalized(_ vector: [Float]) -> [Float] {
        var sum: Float = 0
        for v in vector { sum += v * v }
        guard sum > 0 else { return vector }
        let inverse = 1 / sum.squareRoot()
        return vector.map { $0 * inverse }
    }

    /// Cosine similarity in [-1, 1]. Zero when either vector is zero-length
    /// or the dimensions disagree.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var magA: Float = 0
        var magB: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA.squareRoot() * magB.squareRoot())
    }
}
