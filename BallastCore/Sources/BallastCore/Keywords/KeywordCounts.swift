import Foundation

/// Photo counts per keyword for the inspector's keyword-tree section (U29):
/// subtree-INCLUSIVE — a keyword's count is the number of photos carrying the
/// keyword itself or any descendant, each photo counted once per keyword no
/// matter how many of its descendants it carries (Lightroom semantics).
public enum KeywordCounts {
    /// Keyword-group rows (the tree's first level) key their count by group
    /// id; photos whose keywords have no effective group land under this.
    public static let ungroupedKey: Int64 = -1

    public struct Result: Equatable, Sendable {
        /// Per keyword id, subtree-inclusive.
        public var byKeyword: [Int64: Int]
        /// Per keyword-group id (`ungroupedKey` for groupless), photo-deduped.
        public var byGroup: [Int64: Int]

        public init(byKeyword: [Int64: Int] = [:], byGroup: [Int64: Int] = [:]) {
            self.byKeyword = byKeyword
            self.byGroup = byGroup
        }
    }

    /// O(photos × keywords-per-photo × tree depth); ~30k photos stay in the
    /// low milliseconds. Ids absent from the tree (stale assignment rows) are
    /// skipped rather than miscounted.
    public static func compute(
        keywordIdsByPhoto: [Int64: Set<Int64>],
        tree: KeywordTree
    ) -> Result {
        var result = Result()
        var closure = Set<Int64>()
        var groups = Set<Int64>()
        for ids in keywordIdsByPhoto.values where !ids.isEmpty {
            closure.removeAll(keepingCapacity: true)
            groups.removeAll(keepingCapacity: true)
            for id in ids {
                guard tree.node(id) != nil else { continue }
                groups.insert(tree.effectiveGroupId(of: id) ?? Self.ungroupedKey)
                var current: Int64? = id
                while let node = current.flatMap({ tree.node($0) }) {
                    closure.insert(node.id ?? -1)
                    current = node.parentId
                }
            }
            closure.remove(-1)
            for id in closure {
                result.byKeyword[id, default: 0] += 1
            }
            for id in groups {
                result.byGroup[id, default: 0] += 1
            }
        }
        return result
    }
}
