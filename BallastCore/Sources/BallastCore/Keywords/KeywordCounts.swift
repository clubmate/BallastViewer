import Foundation

/// Photo counts per keyword for the inspector's keyword-tree section (U29):
/// subtree-INCLUSIVE — a keyword's count is the number of photos carrying the
/// keyword itself or any descendant, each photo counted once per keyword no
/// matter how many of its descendants it carries (Lightroom semantics).
public enum KeywordCounts {
    /// O(photos × keywords-per-photo × tree depth); ~30k photos stay in the
    /// low milliseconds. Ids absent from the tree (stale assignment rows) are
    /// skipped rather than miscounted.
    public static func compute(
        keywordIdsByPhoto: [Int64: Set<Int64>],
        tree: KeywordTree
    ) -> [Int64: Int] {
        var counts: [Int64: Int] = [:]
        var closure = Set<Int64>()
        for ids in keywordIdsByPhoto.values where !ids.isEmpty {
            closure.removeAll(keepingCapacity: true)
            for id in ids {
                var current: Int64? = id
                while let node = current.flatMap({ tree.node($0) }) {
                    closure.insert(node.id ?? -1)
                    current = node.parentId
                }
            }
            closure.remove(-1)
            for id in closure {
                counts[id, default: 0] += 1
            }
        }
        return counts
    }
}
