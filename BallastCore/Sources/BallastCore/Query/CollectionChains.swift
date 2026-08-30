/// U41: child Smart Collections. A child's result is its parent's result AND
/// its own rules — evaluated as a CHAIN of independently compiled rule sets,
/// one per ancestor level, so every level keeps its own matchAll/matchAny
/// semantics. The hot paths (counts rebuild, active-collection filter) compile
/// each collection's own rules exactly once and share them across chains.
public struct CompiledRuleChain: Sendable {
    /// Own rules first, then the ancestors' — order is irrelevant to the AND.
    let links: [CompiledRules]

    public init(links: [CompiledRules]) {
        self.links = links
    }

    public func matches(_ photo: PhotoRecord, facts: PhotoQueryFacts) -> Bool {
        links.allSatisfy { $0.matches(photo, facts: facts) }
    }

    /// Compiles every collection once and assembles the ancestor chain per
    /// collection id. A dangling `parentId` (deleted parent mid-flight) ends
    /// the walk; a cycle (impossible through the UI, conceivable in a
    /// hand-edited library) is cut instead of hanging.
    public static func chains(
        collections: [SmartCollectionRecord],
        rulesByCollection: [Int64: [CollectionRuleRecord]]
    ) -> [Int64: CompiledRuleChain] {
        var byId: [Int64: SmartCollectionRecord] = [:]
        var compiledById: [Int64: CompiledRules] = [:]
        for collection in collections {
            guard let id = collection.id else { continue }
            byId[id] = collection
            compiledById[id] = CompiledRules(
                rulesByCollection[id] ?? [], matchAll: collection.matchAll
            )
        }
        var result: [Int64: CompiledRuleChain] = [:]
        result.reserveCapacity(compiledById.count)
        for (id, compiled) in compiledById {
            var links = [compiled]
            var visited: Set<Int64> = [id]
            var cursor = byId[id]?.parentId
            while let current = cursor, visited.insert(current).inserted,
                  let compiledParent = compiledById[current] {
                links.append(compiledParent)
                cursor = byId[current]?.parentId
            }
            result[id] = CompiledRuleChain(links: links)
        }
        return result
    }
}

/// Pure tree lookups over the flat collection list — the sidebar outline, the
/// U7 delete blast radius and the editor's inherited-rules section all derive
/// from these instead of keeping a second hierarchy structure.
public enum CollectionHierarchy {
    /// The subtree below `id` (excluding `id` itself), cycle-safe.
    public static func descendantIds(
        of id: Int64, in collections: [SmartCollectionRecord]
    ) -> Set<Int64> {
        let childrenByParent = Dictionary(
            grouping: collections.filter { $0.parentId != nil }, by: { $0.parentId! }
        )
        var result: Set<Int64> = []
        var stack = [id]
        while let next = stack.popLast() {
            for child in childrenByParent[next] ?? [] {
                guard let childId = child.id, result.insert(childId).inserted else { continue }
                stack.append(childId)
            }
        }
        return result
    }

    /// The ancestor records of `id`, nearest first ("parent, grandparent, …"),
    /// cycle-safe. The editor lists their rules greyed out, nearest last.
    public static func ancestors(
        of id: Int64, in collections: [SmartCollectionRecord]
    ) -> [SmartCollectionRecord] {
        let byId = Dictionary(uniqueKeysWithValues: collections.compactMap { record in
            record.id.map { ($0, record) }
        })
        var result: [SmartCollectionRecord] = []
        var visited: Set<Int64> = [id]
        var cursor = byId[id]?.parentId
        while let current = cursor, visited.insert(current).inserted, let record = byId[current] {
            result.append(record)
            cursor = record.parentId
        }
        return result
    }
}
