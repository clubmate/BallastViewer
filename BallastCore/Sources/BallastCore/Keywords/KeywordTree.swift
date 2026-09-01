import Foundation

/// Immutable in-memory view of the keyword table. Rebuild it from records after
/// any vocabulary mutation — construction is O(n log n) and trivial even for
/// tens of thousands of keywords.
///
/// Path strings (`"PEOPLE > ANNA"`) are derived here, never stored (fixes C4).
/// Because the tree is immutable, every derived per-node value — path, folded
/// path, effective group — is precomputed in one DFS at construction: the same
/// path is shared by thousands of photos, and walking ancestors per lookup was
/// the single hottest string cost in facts/counts rebuilds and autocomplete.
public struct KeywordTree: Sendable {
    public static let separator = " > "

    private let nodesById: [Int64: KeywordRecord]
    /// Children per parent (nil = top level), name-sorted — siblings are always
    /// alphabetical, unlike drag-ordered groups (Q19).
    private let childIdsByParent: [Int64?: [Int64]]
    /// Memoized derived data, keyed by node id. Nodes unreachable from the
    /// roots (a parentId cycle in a corrupt DB) are absent and fall back to
    /// the guarded ancestor walk.
    private let pathById: [Int64: String]
    private let foldedPathById: [Int64: String]
    private let effectiveGroupById: [Int64: Int64]
    /// Every reachable node id in depth-first, name-sorted order — the order
    /// `firstMatch` and the autocomplete corpus iterate in (Q16/Q17).
    private let depthFirstIds: [Int64]
    /// (folded, display) path per `depthFirstIds` entry — the autocomplete
    /// corpus, built once so a keystroke is a plain `contains` scan.
    private let foldedCorpus: [(folded: String, path: String)]

    public init(records: [KeywordRecord]) {
        var byId: [Int64: KeywordRecord] = [:]
        var byParent: [Int64?: [KeywordRecord]] = [:]
        for record in records {
            guard let id = record.id else { continue }
            byId[id] = record
            byParent[record.parentId, default: []].append(record)
        }
        nodesById = byId
        let children = byParent.mapValues { siblings in
            // Alphabetical for humans (Q19), not by code point: "ÄPFEL" sorts
            // next to "APFEL", not after "ZEBRA". Ties break by id for stability.
            siblings
                .sorted { a, b in
                    switch a.name.localizedStandardCompare(b.name) {
                    case .orderedAscending: true
                    case .orderedDescending: false
                    case .orderedSame: (a.id ?? 0) < (b.id ?? 0)
                    }
                }
                .compactMap(\.id)
        }
        childIdsByParent = children

        var paths: [Int64: String] = [:]
        var folded: [Int64: String] = [:]
        var groups: [Int64: Int64] = [:]
        var order: [Int64] = []
        var corpus: [(folded: String, path: String)] = []
        paths.reserveCapacity(byId.count)
        folded.reserveCapacity(byId.count)
        order.reserveCapacity(byId.count)
        corpus.reserveCapacity(byId.count)
        // Children are pushed reversed so popLast yields them in sorted
        // order: the single DFS also produces the depth-first id list.
        var stack: [(id: Int64, parentPath: String?, parentGroup: Int64?)] =
            (children[nil] ?? []).reversed().map { ($0, nil, nil) }
        while let (id, parentPath, parentGroup) = stack.popLast() {
            guard let node = byId[id] else { continue }
            let path = parentPath.map { $0 + Self.separator + node.name } ?? node.name
            let foldedPath = CaseInsensitiveMatch.fold(path)
            paths[id] = path
            folded[id] = foldedPath
            order.append(id)
            corpus.append((foldedPath, path))
            let effective = node.groupId ?? parentGroup
            if let effective { groups[id] = effective }
            for child in (children[id] ?? []).reversed() {
                stack.append((child, path, effective))
            }
        }
        pathById = paths
        foldedPathById = folded
        effectiveGroupById = groups
        depthFirstIds = order
        foldedCorpus = corpus
    }

    public var isEmpty: Bool { nodesById.isEmpty }
    public var count: Int { nodesById.count }

    public func node(_ id: Int64) -> KeywordRecord? {
        nodesById[id]
    }

    public var rootIds: [Int64] {
        childIdsByParent[nil] ?? []
    }

    public func children(of id: Int64) -> [Int64] {
        childIdsByParent[id] ?? []
    }

    /// Root-first name chain of a node — the file-facing keyword path.
    public func pathComponents(of id: Int64) -> [String] {
        var components: [String] = []
        var visited: Set<Int64> = []
        var current = nodesById[id]
        // The schema cannot express a parentId cycle through the UI, but a
        // corrupt or hand-edited DB can — guard against an endless walk.
        while let record = current, let recordId = record.id, visited.insert(recordId).inserted {
            components.append(record.name)
            current = record.parentId.flatMap { nodesById[$0] }
        }
        return components.reversed()
    }

    /// `"PEOPLE > TEAM > ANNA"` — uppercase by storage invariant. O(1).
    public func path(of id: Int64) -> String {
        pathById[id] ?? pathComponents(of: id).joined(separator: Self.separator)
    }

    /// The case-folded twin of `path(of:)`, for fold-consistent substring
    /// matching without per-lookup ICU work. O(1).
    public func foldedPath(of id: Int64) -> String {
        foldedPathById[id] ?? CaseInsensitiveMatch.fold(path(of: id))
    }

    /// All node ids in depth-first, name-sorted order. Every node — not just
    /// leaves — is assignable (Q17). Precomputed at construction; O(1).
    public func allIdsDepthFirst() -> [Int64] {
        depthFirstIds
    }

    public func allPaths() -> [String] {
        foldedCorpus.map(\.path)
    }

    /// (folded, display) pairs of every path — the autocomplete corpus.
    /// Folding happened once at construction; matching is a plain `contains`.
    public func allFoldedPaths() -> [(folded: String, path: String)] {
        foldedCorpus
    }

    /// First node matching `name` (single component, case-insensitive) in
    /// depth-first order — first match wins, ambiguity is not expressible (Q16).
    public func firstMatch(named name: String) -> Int64? {
        let needle = KeywordDAO.normalize(name)
        return depthFirstIds.first { nodesById[$0]?.name == needle }
    }

    /// Descends the tree along path components (case-insensitive).
    public func find(pathComponents components: [String]) -> Int64? {
        var parentId: Int64? = nil
        var currentId: Int64? = nil
        for rawName in components {
            let name = KeywordDAO.normalize(rawName)
            let siblings = childIdsByParent[parentId] ?? []
            guard let match = siblings.first(where: { nodesById[$0]?.name == name }) else {
                return nil
            }
            currentId = match
            parentId = match
        }
        return currentId
    }

    /// The node's own group, or the nearest grouped ancestor's. This is what
    /// group rules and chip colours use, so nested keywords under a grouped
    /// root behave as group members (C2). O(1).
    public func effectiveGroupId(of id: Int64) -> Int64? {
        if let cached = effectiveGroupById[id] { return cached }
        if pathById[id] != nil { return nil }  // reachable, genuinely ungrouped
        // Unreachable (cyclic) node: guarded walk.
        var visited: Set<Int64> = []
        var current = nodesById[id]
        while let record = current, let recordId = record.id, visited.insert(recordId).inserted {
            if let groupId = record.groupId { return groupId }
            current = record.parentId.flatMap { nodesById[$0] }
        }
        return nil
    }

    public func descendants(of id: Int64) -> [Int64] {
        var result: [Int64] = []
        var stack = children(of: id)
        while let next = stack.popLast() {
            result.append(next)
            stack.append(contentsOf: children(of: next))
        }
        return result
    }

    // MARK: Delta derivations

    /// Every record currently in the tree — the base for delta rebuilds
    /// without a DB round-trip after a vocabulary mutation.
    public var allRecords: [KeywordRecord] { Array(nodesById.values) }

    /// Names are normalised (`KeywordDAO.normalize`) on the way in so the
    /// in-memory tree can never diverge from the DB's storage invariant.
    public func inserting(_ record: KeywordRecord) -> KeywordTree {
        inserting(contentsOf: [record])
    }

    public func inserting(contentsOf records: [KeywordRecord]) -> KeywordTree {
        KeywordTree(records: allRecords + records.map(Self.normalized))
    }

    public func renaming(_ id: Int64, to name: String) -> KeywordTree {
        let normalized = KeywordDAO.normalize(name)
        return KeywordTree(records: allRecords.map { record in
            guard record.id == id else { return record }
            var renamed = record
            renamed.name = normalized
            return renamed
        })
    }

    private static func normalized(_ record: KeywordRecord) -> KeywordRecord {
        var copy = record
        copy.name = KeywordDAO.normalize(record.name)
        return copy
    }

    public func deletingSubtree(_ id: Int64) -> KeywordTree {
        let removed = Set([id] + descendants(of: id))
        return KeywordTree(records: allRecords.filter { record in
            record.id.map { !removed.contains($0) } ?? false
        })
    }

    /// Mirrors `KeywordDAO.setGroup`: re-homes one node into `groupId`
    /// (nil = ad-hoc). Descendants follow through effective-group inheritance.
    public func settingGroup(_ groupId: Int64?, of id: Int64) -> KeywordTree {
        KeywordTree(records: allRecords.map { record in
            guard record.id == id else { return record }
            var moved = record
            moved.groupId = groupId
            return moved
        })
    }

    /// Mirrors `KeywordDAO.setAIDescription` (U48): swaps one node's AI
    /// description (nil = opted out of suggestions).
    public func settingAIDescription(_ description: String?, of id: Int64) -> KeywordTree {
        KeywordTree(records: allRecords.map { record in
            guard record.id == id else { return record }
            var changed = record
            changed.aiDescription = description
            return changed
        })
    }

    /// Mirrors the FK `onDelete: .setNull` of a group deletion: members become
    /// ad-hoc keywords (C3).
    public func removingGroup(_ groupId: Int64) -> KeywordTree {
        KeywordTree(records: allRecords.map { record in
            guard record.groupId == groupId else { return record }
            var freed = record
            freed.groupId = nil
            return freed
        })
    }
}
