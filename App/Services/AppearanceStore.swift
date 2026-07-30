import BallastCore
import Foundation
import Observation

/// App-level preferences behind Settings ▸ Appearance (spec §9.9), persisted in
/// UserDefaults — they describe this Mac, not a library. Colors are stored
/// canonical `#RRGGBBAA` (C8).
@MainActor @Observable
final class AppearanceStore {
    private static let spacingKey = "gridSpacing"
    private static let backgroundKey = "backgroundColor"
    private static let debounceKey = "midiDebounceTime"

    static let defaultBackgroundHex = "#1E1E1EFF"

    /// Grid gap and outer padding in points, 0–50 (Q23: one value for both).
    var gridSpacing: Double {
        didSet { UserDefaults.standard.set(gridSpacing, forKey: Self.spacingKey) }
    }

    /// Centre-pane background, canonical `#RRGGBBAA`.
    var backgroundHex: String {
        didSet { UserDefaults.standard.set(backgroundHex, forKey: Self.backgroundKey) }
    }

    /// Per-action MIDI debounce in milliseconds, 0 = off. Stored now so the
    /// Appearance tab is complete; consumed by the MIDI service in step 11.
    var midiDebounceMs: Int {
        didSet { UserDefaults.standard.set(midiDebounceMs, forKey: Self.debounceKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        gridSpacing = defaults.object(forKey: Self.spacingKey) as? Double ?? 12
        // Re-canonicalise on read so a hand-edited plist can't smuggle a
        // malformed value into the view layer.
        backgroundHex = defaults.string(forKey: Self.backgroundKey)
            .flatMap(HexColor.parse)?.formatted ?? Self.defaultBackgroundHex
        midiDebounceMs = defaults.integer(forKey: Self.debounceKey)
    }
}
