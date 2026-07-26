import BallastCore
import SwiftUI

/// Menu shortcut derived from the user's key map, so remapping in Settings
/// updates the menus live (spec §14.2/§14.3).
///
/// Only chords carrying ⌘ or ⌃ become real menu key equivalents: dispatch runs
/// through the app-wide key monitor, which deliberately passes events on while
/// text fields are focused — a bare-key menu equivalent (like `3`) would then
/// fire mid-typing. Modifier-less bindings still work everywhere via the
/// monitor; their menu items just show no shortcut label.
@MainActor
func menuShortcut(for action: AppAction, in map: KeyMap) -> KeyboardShortcut? {
    guard let chord = map.chord(for: .app(action)),
          !chord.modifiers.intersection([.cmd, .ctrl]).isEmpty
    else { return nil }

    let key: KeyEquivalent
    switch chord.key {
    case "UpArrow": key = .upArrow
    case "DownArrow": key = .downArrow
    case "LeftArrow": key = .leftArrow
    case "RightArrow": key = .rightArrow
    case "Space": key = .space
    case "Escape": key = .escape
    case "Return": key = .return
    case "Delete": key = .delete
    case "Tab": key = .tab
    default:
        guard let character = chord.key.first else { return nil }
        key = KeyEquivalent(character)
    }
    var modifiers: EventModifiers = []
    if chord.modifiers.contains(.ctrl) { modifiers.insert(.control) }
    if chord.modifiers.contains(.opt) { modifiers.insert(.option) }
    if chord.modifiers.contains(.shift) { modifiers.insert(.shift) }
    if chord.modifiers.contains(.cmd) { modifiers.insert(.command) }
    return KeyboardShortcut(key, modifiers: modifiers)
}

/// The Photo menu (spec §14.2). Every item is disabled without an anchor.
struct PhotoCommands: Commands {
    let center: CenterViewModel
    let dispatcher: ActionDispatcher
    let keyMap: KeyMapStore

    private var hasAnchor: Bool { center.selection.anchorId != nil }

    var body: some Commands {
        CommandMenu("Photo") {
            item("Next Photo", action: .nextPhoto)
            item("Previous Photo", action: .previousPhoto)
            Divider()
            item("Rotate Clockwise", action: .rotate)
            Menu("Rating") {
                item("0 Stars", action: .rate0)
                item("1 Star", action: .rate1)
                item("2 Stars", action: .rate2)
                item("3 Stars", action: .rate3)
                item("4 Stars", action: .rate4)
                item("5 Stars", action: .rate5)
            }
            .disabled(!hasAnchor)
        }
    }

    @ViewBuilder
    private func item(_ title: String, action: AppAction) -> some View {
        let button = Button(title) { dispatcher.dispatch(.app(action), source: .menu) }
            .disabled(!hasAnchor)
        if let shortcut = menuShortcut(for: action, in: keyMap.map) {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }
}
