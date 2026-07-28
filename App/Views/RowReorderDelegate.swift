import SwiftUI

/// Live drag-reordering shared by the sidebar and the keyword-group editor:
/// rows shuffle under the cursor in `dropEntered`; the drop itself is a no-op.
/// Reordering within one id list only.
struct RowReorderDelegate: DropDelegate {
    let targetId: Int64
    @Binding var draggedId: Int64?
    let orderedIds: [Int64]
    let reorder: ([Int64]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedId, draggedId != targetId,
              let from = orderedIds.firstIndex(of: draggedId),
              let to = orderedIds.firstIndex(of: targetId)
        else { return }
        var ids = orderedIds
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        reorder(ids)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedId = nil
        return true
    }
}
