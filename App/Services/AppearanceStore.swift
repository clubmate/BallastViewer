import BallastCore
import Foundation
import Observation
import SwiftUI

/// App-level preferences behind Settings ▸ Appearance and ▸ MIDI (spec §9.9),
/// persisted in UserDefaults — they describe this Mac, not a library. Colors
/// are stored canonical `#RRGGBBAA` (C8).
@MainActor @Observable
final class AppearanceStore {
    private static let backgroundKey = "backgroundColor"
    private static let selectionKey = "selectionColor"
    private static let debounceKey = "midiDebounceTime"
    private static let outputKey = "midiOutputDestination"

    static let defaultBackgroundHex = "#1E1E1EFF"
    static let defaultSelectionHex = "#007AFFFF"

    /// Centre-pane background, canonical `#RRGGBBAA`.
    /// The parsed background — the stored hex is validated on load, so the
    /// default fallback only covers a programmatic write of garbage.
    var backgroundColor: Color {
        Color(hex: backgroundHex) ?? Color(hex: Self.defaultBackgroundHex)!
    }

    var backgroundHex: String {
        didSet { UserDefaults.standard.set(backgroundHex, forKey: Self.backgroundKey) }
    }

    /// Border colour of selected grid cells, canonical `#RRGGBBAA`.
    var selectionColor: Color {
        Color(hex: selectionHex) ?? Color(hex: Self.defaultSelectionHex)!
    }

    var selectionHex: String {
        didSet { UserDefaults.standard.set(selectionHex, forKey: Self.selectionKey) }
    }

    /// Per-action MIDI debounce in milliseconds, 0 = off (spec §13.4).
    var midiDebounceMs: Int {
        didSet { UserDefaults.standard.set(midiDebounceMs, forKey: Self.debounceKey) }
    }

    /// LED output destination by display name; "" = all destinations (the
    /// original's broadcast behaviour, U12 adds the picker).
    var midiOutputDestination: String {
        didSet { UserDefaults.standard.set(midiOutputDestination, forKey: Self.outputKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        // Re-canonicalise on read so a hand-edited plist can't smuggle a
        // malformed value into the view layer.
        backgroundHex = defaults.string(forKey: Self.backgroundKey)
            .flatMap(HexColor.parse)?.formatted ?? Self.defaultBackgroundHex
        selectionHex = defaults.string(forKey: Self.selectionKey)
            .flatMap(HexColor.parse)?.formatted ?? Self.defaultSelectionHex
        midiDebounceMs = defaults.integer(forKey: Self.debounceKey)
        midiOutputDestination = defaults.string(forKey: Self.outputKey) ?? ""
    }
}
