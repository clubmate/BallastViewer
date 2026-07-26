import Foundation

/// Immutable in-memory view of the keyword table. Rebuild it from records after
/// any vocabulary mutation — construction is O(n log n) and trivial even for
/// tens of thousands of keywords.
///
/// Path strings (`"PEOPLE > ANNA"`) are derived here, never stored (fixes C4).
public struct KeywordTree: Sendable {
    public static let separator = " > "

    private let nodesById: [Int64: KeywordRecord]
    /// Children per parent (nil = top level), name-sorted — siblings are always
    /// alphabetical, unlike drag-ordered groups (Q19).
    private let childIdsByParent: [Int64?: [Int64]]

    public init(records: [KeywordRecord]) {
        var byId: [Int64: KeywordRecord] = [:]
        var byParent: [Int64?: [KeywordRecord]] = [:]
        for record in records {
            guard let id = record.id else { continue }
            byId[id] = record
            byParent[record.parentId, default: []].append(record)
        }
        nodesById = byId
        childIdsByParent = byParent.mapValues { siblings in
            siblings
                .sorted { ($0.name, $0.id ?? 0) < ($1.name, $1.id ?? 0) }
                .compactMap(\.id)
        }
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

    public func pathComponents(of id: Int64) -> [String] {
        var components: [String] = []
        var current = nodesById[id]
        while let record = current {
            components.append(record.name)
            current = record.parentId.flatMap { nodesById[$0] }
        }
        return components.reversed()
    }

    /// `"PEOPLE > TEAM > ANNA"` — uppercase by storage invariant.
    public func path(of id: Int64) -> String {
        pathComponents(of: id).joined(separator: Self.separator)
    }

    /// All node ids in depth-first, name-sorted order. Every node — not just
    /// leaves — is assignable (Q17).
    public func allIdsDepthFirst() -> [Int64] {
        var result: [Int64] = []
        var stack: [Int64] = rootIds.reversed()
        while let id = stack.popLast() {
            result.append(id)
            stack.append(contentsOf: children(of: id).reversed())
        }
        return result
    }

    public func allPaths() -> [String] {
        allIdsDepthFirst().map { path(of: $0) }
    }

    /// First node matching `name` (single component, case-insensitive) in
    /// depth-first order — first match wins, ambiguity is not expressible (Q16).
    public func firstMatch(named name: String) -> Int64? {
        let needle = KeywordDAO.normalize(name)
        return allIdsDepthFirst().first { nodesById[$0]?.name == needle }
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
    /// root behave as group members (C2).
    public func effectiveGroupId(of id: Int64) -> Int64? {
        var current = nodesById[id]
        while let record = current {
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
}
