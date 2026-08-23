import SwiftUI

/// One live drag-reorder shared by the sidebar and the keyword-group editor:
/// rows shuffle under the cursor against a LOCAL copy of the order, and the
/// model is written when the drag ends — `dropEntered` used to persist a
/// reorder (sync write + event) for every row crossed. Reordering within one
/// id list only; each list keeps its own session so ids of different tables
/// never collide.
struct RowReorderSession {
    private(set) var draggedId: Int64?
    /// The visual order while a drag is in flight; nil = render the model.
    private(set) var order: [Int64]?
    /// The last order handed to `commit` — a repeated `flush` is a no-op.
    private var committed: [Int64] = []
    private var commit: (([Int64]) -> Void)?

    /// Starts a session from the row's `onDrag`. A session still open from a
    /// drag that was cancelled outside the list is flushed first.
    mutating func begin(draggedId: Int64, order: [Int64], commit: @escaping ([Int64]) -> Void) {
        flush()
        self.draggedId = draggedId
        self.order = order
        committed = order
        self.commit = commit
    }

    /// Moves the dragged row before/after `targetId` in the local copy.
    mutating func move(over targetId: Int64) {
        guard let draggedId, draggedId != targetId, var ids = order,
              let from = ids.firstIndex(of: draggedId),
              let to = ids.firstIndex(of: targetId)
        else { return }
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        order = ids
    }

    /// Persists the local order if it changed. Safe to call mid-drag (the
    /// session stays open), so a drag leaving the list commits what the user
    /// saw without breaking the shuffle if it comes back.
    mutating func flush() {
        if let order, order != committed {
            commit?(order)
            committed = order
        }
    }

    /// Flush and end the session (the drop landed).
    mutating func end() {
        flush()
        draggedId = nil
        order = nil
        commit = nil
    }

    /// The items in the session's order while a drag is in flight; the model
    /// order otherwise (also when the lists disagree — a row was added or
    /// removed under the drag).
    func ordered<T>(_ items: [T], id: KeyPath<T, Int64?>) -> [T] {
        guard let order, Set(order) == Set(items.compactMap { $0[keyPath: id] }) else { return items }
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return items.sorted {
            ($0[keyPath: id].flatMap { position[$0] } ?? .max)
                < ($1[keyPath: id].flatMap { position[$0] } ?? .max)
        }
    }
}

/// Per-row delegate: shuffles the session's local order in `dropEntered`,
/// commits on drop.
struct RowReorderDelegate: DropDelegate {
    let targetId: Int64
    @Binding var session: RowReorderSession

    func dropEntered(info: DropInfo) {
        session.move(over: targetId)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        session.end()
        return true
    }
}

/// Attached to the list container: a drop between rows ends the session, and
/// the drag leaving the container flushes it — so a drag released outside
/// every row (or outside the window) still persists the order the user saw.
/// `dropExited` may also fire when the pointer moves onto a child row; the
/// flush is idempotent and keeps the session open, so that costs at most one
/// extra write per real move.
struct RowReorderEndDelegate: DropDelegate {
    let flush: () -> Void
    let end: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        flush()
    }

    func performDrop(info: DropInfo) -> Bool {
        end()
        return true
    }
}
