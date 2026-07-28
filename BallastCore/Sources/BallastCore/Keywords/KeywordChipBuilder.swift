import Foundation

/// One assigned-keyword chip in the inspector (spec §8.5).
public struct KeywordChip: Equatable, Identifiable, Sendable {
    public var id: Int64
    /// Derived full path, e.g. `"PEOPLE > ANNA"`.
    public var path: String
    /// Effective group colour ("#RRGGBB"); nil = ungrouped → grey.
    public var colorHex: String?

    public init(id: Int64, path: String, colorHex: String?) {
        self.id = id
        self.path = path
        self.colorHex = colorHex
    }
}

public enum KeywordChipBuilder {
    /// The keywords common to ALL given photos — the intersection, not the
    /// union (Q14). Toggling a visible chip therefore affects every photo.
    public static func commonKeywordIds(
        photoIds: [Int64],
        keywordIdsByPhoto: [Int64: Set<Int64>]
    ) -> Set<Int64> {
        guard let first = photoIds.first else { return [] }
        var common = keywordIdsByPhoto[first] ?? []
        for photoId in photoIds.dropFirst() {
            if common.isEmpty { break }
            common.formIntersection(keywordIdsByPhoto[photoId] ?? [])
        }
        return common
    }

    /// Chips ordered by group position (Q18: group drag-order is semantic),
    /// ungrouped last, then alphabetically by path. Colour = effective group
    /// (nearest grouped ancestor, C2).
    public static func chips(
        forKeywordIds ids: some Sequence<Int64>,
        tree: KeywordTree,
        groups: [KeywordGroupRecord]
    ) -> [KeywordChip] {
        var priorityByGroupId: [Int64: Int] = [:]
        var colorByGroupId: [Int64: String] = [:]
        for (position, group) in groups.enumerated() {
            guard let groupId = group.id else { continue }
            priorityByGroupId[groupId] = position
            colorByGroupId[groupId] = group.color
        }
        return ids
            .compactMap { id -> (priority: Int, chip: KeywordChip)? in
                guard tree.node(id) != nil else { return nil }
                let groupId = tree.effectiveGroupId(of: id)
                return (
                    priority: groupId.flatMap { priorityByGroupId[$0] } ?? .max,
                    chip: KeywordChip(
                        id: id,
                        path: tree.path(of: id),
                        colorHex: groupId.flatMap { colorByGroupId[$0] }
                    )
                )
            }
            .sorted { ($0.priority, $0.chip.path) < ($1.priority, $1.chip.path) }
            .map(\.chip)
    }
}
