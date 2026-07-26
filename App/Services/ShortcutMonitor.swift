import AppKit
import BallastCore

extension KeyChord {
    /// Canonical chord for a key-down event: keyCode for the special keys,
    /// otherwise the base character with no modifiers applied (so shift+5 is
    /// `shift+5`, not `%`).
    init?(event: NSEvent) {
        var modifiers: Modifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.ctrl) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.opt) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.cmd) }

        let specialByKeyCode: [UInt16: String] = [
            126: "UpArrow", 125: "DownArrow", 123: "LeftArrow", 124: "RightArrow",
            49: "Space", 53: "Escape", 36: "Return", 51: "Delete", 48: "Tab",
        ]
        let key: String
        if let special = specialByKeyCode[event.keyCode] {
            key = special
        } else if let characters = event.characters(byApplyingModifiers: [])
            ?? event.charactersIgnoringModifiers,
            let first = characters.first, !first.isWhitespace, first.isLetter || first.isNumber
                || first.isPunctuation || first.isSymbol {
            key = String(first).lowercased()
        } else {
            return nil
        }
        self.init(modifiers: modifiers, key: key)
    }
}

/// App-wide key handling via a local event monitor — shortcuts keep working
/// after mode or collection switches without the centre pane needing AppKit
/// focus (spec §10.5). Unmatched events pass on to the menu system.
@MainActor
final class ShortcutMonitor {
    private let keyMap: KeyMapStore
    private let dispatcher: ActionDispatcher
    /// Monitor token — never removed; this object lives as long as the app.
    private var monitor: Any?

    init(keyMap: KeyMapStore, dispatcher: ActionDispatcher) {
        self.keyMap = keyMap
        self.dispatcher = dispatcher
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // The monitor always fires on the main thread; NSEvent is not
            // Sendable, so it crosses into the assumeIsolated closure boxed
            // and only the Sendable "consumed" flag comes back out.
            let box = EventBox(event: event)
            let consumed = MainActor.assumeIsolated {
                self?.consume(box.event) ?? false
            }
            return consumed ? nil : event
        }
    }

    private struct EventBox: @unchecked Sendable {
        let event: NSEvent
    }

    /// True when the event matched a binding and was dispatched.
    private func consume(_ event: NSEvent) -> Bool {
        guard Self.shouldHandle(event),
              let chord = KeyChord(event: event),
              let command = keyMap.map.command(for: chord)
        else { return false }
        dispatcher.dispatch(command, source: .keyboard)
        return true
    }

    /// Shortcuts stay out of text entry (Q21 — search lands in step 9, the
    /// suppression mechanism is load-bearing now), out of panels (save/open
    /// dialogs) and out of windows showing a sheet (alerts).
    private static func shouldHandle(_ event: NSEvent) -> Bool {
        guard let window = event.window,
              !(window is NSPanel),
              window.attachedSheet == nil
        else { return false }
        if window.firstResponder is NSText || window.firstResponder is NSTextView {
            return false
        }
        return true
    }
}
