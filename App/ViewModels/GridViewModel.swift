import AppKit
import BallastCore
import Observation

/// Lightweight value the grid renders — decoupled from PhotoRecord so the
/// view layer never touches DB types directly.
struct GridPhoto: Identifiable, Hashable, Sendable {
    let id: Int64
    let path: String
    let orientation: Int
}

@MainActor @Observable
final class GridViewModel {
    var selection = SelectionModel()
    /// 1–10, default 5 (spec §9.3). Session-only by design (Q24).
    var columnCount = 5

    /// Mouse selection per spec §9.3: click / shift-click / cmd-click.
    func handleClick(on id: Int64, modifiers: NSEvent.ModifierFlags, orderedIds: [Int64]) {
        if modifiers.contains(.command) {
            selection.toggle(id)
        } else if modifiers.contains(.shift) {
            selection.selectRange(to: id, in: orderedIds)
        } else {
            selection.selectSingle(id)
        }
    }
}
