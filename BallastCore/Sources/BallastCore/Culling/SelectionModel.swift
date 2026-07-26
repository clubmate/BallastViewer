import Foundation

/// Selection state per spec §10.1/§10.2: a selection set plus an *anchor*
/// (the "current" photo — target of range selection, inspector display,
/// keyboard actions and MIDI LED feedback). The two can disagree: toggling
/// the anchor out of the selection leaves other photos selected, anchor nil.
public struct SelectionModel: Equatable, Sendable {
    public private(set) var selectedIds: Set<Int64> = []
    public private(set) var anchorId: Int64?

    public init() {}

    public func isSelected(_ id: Int64) -> Bool {
        selectedIds.contains(id)
    }

    public var isEmpty: Bool { selectedIds.isEmpty }

    /// Anchor = id, selection = {id}. With nil, clears both.
    public mutating func selectSingle(_ id: Int64?) {
        if let id {
            selectedIds = [id]
            anchorId = id
        } else {
            selectedIds = []
            anchorId = nil
        }
    }

    /// Cmd-click: present → remove (anchor nil if it was the anchor);
    /// absent → insert and become the anchor.
    public mutating func toggle(_ id: Int64) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
            if anchorId == id { anchorId = nil }
        } else {
            selectedIds.insert(id)
            anchorId = id
        }
    }

    /// Drops selected ids that are no longer visible; the anchor follows the
    /// same rule. Used after list membership changes that did not remove the
    /// anchor (the neighbour rule handles that case).
    public mutating func prune(keeping visibleIds: Set<Int64>) {
        selectedIds.formIntersection(visibleIds)
        if let anchorId, !selectedIds.contains(anchorId) {
            self.anchorId = nil
        }
    }

    /// Shift-click: everything between the anchor and `id` in the *visible*
    /// order, inclusive; the anchor moves to `id`. Without an anchor this
    /// degrades to a single selection.
    public mutating func selectRange(to id: Int64, in orderedIds: [Int64]) {
        guard let anchorId,
              let anchorIndex = orderedIds.firstIndex(of: anchorId),
              let targetIndex = orderedIds.firstIndex(of: id)
        else {
            selectSingle(id)
            return
        }
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedIds = Set(orderedIds[range])
        self.anchorId = id
    }
}
