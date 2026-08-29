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
    /// True while a Settings key recorder is capturing — the recorder's own
    /// monitor must see the press instead of the dispatcher.
    static var recorderActive = false

    /// The one window whose key events drive shortcuts, registered by
    /// MainWindow on appearance. A whitelist — everything else (Settings,
    /// panels, future windows) is ignored by construction, instead of sniffing
    /// undocumented window identifiers.
    static weak var mainWindow: NSWindow?

    private let keyMap: KeyMapStore
    private let dispatcher: ActionDispatcher
    /// Monitor tokens — never removed; this object lives as long as the app.
    private var monitor: Any?
    private var clickMonitor: Any?

    private struct EventBox: @unchecked Sendable {
        let event: NSEvent
    }

    init(keyMap: KeyMapStore, dispatcher: ActionDispatcher) {
        self.keyMap = keyMap
        self.dispatcher = dispatcher
        monitor = LocalKeyDownMonitor.install { [weak self] event in
            self?.consume(event) ?? false
        }
        // Clicking anywhere outside a focused text field hands the keyboard
        // back to the grid (user request 2026-08-30): grid cells and most
        // SwiftUI controls never claim first-responder status, so the field
        // stayed focused — and Q21 kept suppressing every shortcut — until
        // Escape or a committing Return. Standard app behaviour, emulated
        // globally because SwiftUI surfaces won't do it themselves.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            let box = EventBox(event: event)
            MainActor.assumeIsolated { Self.releaseTextFocusAfterClick(box.event) }
            return event
        }
    }

    /// Resigns a focused text field when a click lands anywhere that is not
    /// itself a text control. Mouse-UP, and the release deferred to after the
    /// event is fully dispatched: a click on a suggestion-dropdown row (an
    /// in-window overlay) must reach its button first — releasing on
    /// mouse-down tore the dropdown down before the row's mouse-up landed and
    /// swallowed the pick. The async re-check skips the release when the
    /// click itself moved focus into another field, or the row's action
    /// already released it.
    private static func releaseTextFocusAfterClick(_ event: NSEvent) {
        guard let window = event.window,
              window === mainWindow,
              window.attachedSheet == nil,
              window.firstResponder is NSText,
              let contentView = window.contentView
        else { return }
        // A click into any text control claims or keeps focus itself.
        var view = contentView.hitTest(event.locationInWindow)
        while let current = view {
            if current is NSText || current is NSTextField { return }
            view = current.superview
        }
        DispatchQueue.main.async {
            guard let window = mainWindow, window.firstResponder is NSText else { return }
            window.makeFirstResponder(nil)
        }
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

    /// Shortcuts fire only in the registered main window (never Settings or
    /// panels), never while it shows a sheet (alerts), and stay out of text
    /// entry (Q21 — pressing `5` in the search field must type, never rate).
    private static func shouldHandle(_ event: NSEvent) -> Bool {
        guard !recorderActive,
              let window = event.window,
              window === mainWindow,
              window.attachedSheet == nil
        else { return false }
        // NSTextView is an NSText — one check covers both field editors and views.
        guard let text = window.firstResponder as? NSText else { return true }
        // Culling flow: after committing a keyword the entry keeps focus so the
        // next keyword can be typed, but an EMPTY field has no caret to move
        // and no suggestion list (KeywordAutocomplete returns nothing for an
        // empty query), so the arrow keys may navigate photos instead of
        // being swallowed. Anything typed still goes to the field.
        return text.string.isEmpty && Self.arrowKeyCodes.contains(event.keyCode)
    }

    /// Left, right, down, up.
    private static let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]
}

/// Shared local key-down monitor plumbing (ShortcutMonitor, PhotoPickerModel).
@MainActor
enum LocalKeyDownMonitor {
    private struct EventBox: @unchecked Sendable {
        let event: NSEvent
    }

    /// Installs a monitor whose `consume` callback runs on the MainActor; a
    /// consumed event is swallowed, anything else passes on to the menu
    /// system. Returns the token for `NSEvent.removeMonitor`.
    static func install(_ consume: @escaping @MainActor (NSEvent) -> Bool) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // The monitor always fires on the main thread; NSEvent is not
            // Sendable, so it crosses into the assumeIsolated closure boxed
            // and only the Sendable "consumed" flag comes back out.
            let box = EventBox(event: event)
            let consumed = MainActor.assumeIsolated { consume(box.event) }
            return consumed ? nil : event
        }
    }
}
