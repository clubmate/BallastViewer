import BallastCore
import SwiftUI

/// The View menu items (spec §14.3): three panel toggles whose titles reflect
/// the current state and whose shortcuts come live from the key map. Added to
/// the system View menu rather than a second custom one.
struct ViewCommands: Commands {
    let center: CenterViewModel
    let dispatcher: ActionDispatcher
    let keyMap: KeyMapStore

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            toggle(shown: center.showLeftPanel, name: "Left Panel", action: .toggleLeftPanel)
            toggle(shown: center.showRightPanel, name: "Right Panel", action: .toggleRightPanel)
            toggle(shown: center.showBottomPanel, name: "Bottom Panel", action: .toggleBottomPanel)
            Divider()
            // U6: grid badges, default on. Not one of the nineteen actions —
            // a plain menu toggle without a recordable shortcut.
            Button(center.showBadges ? "Hide Badges" : "Show Badges") {
                center.showBadges.toggle()
            }
        }
    }

    @ViewBuilder
    private func toggle(shown: Bool, name: String, action: AppAction) -> some View {
        let button = Button(shown ? "Hide \(name)" : "Show \(name)") {
            dispatcher.dispatch(.app(action), source: .menu)
        }
        if let shortcut = menuShortcut(for: action, in: keyMap.map) {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }
}
