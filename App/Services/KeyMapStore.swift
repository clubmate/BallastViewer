import BallastCore
import Foundation
import Observation

/// Owns the user's key map: writes the spec §12.3 defaults on first launch,
/// persists every change, and republishes so menus update live. The editor UI
/// arrives in step 9; the storage model is final now.
@MainActor @Observable
final class KeyMapStore {
    private static let defaultsKey = "keyboardShortcuts"

    private(set) var map: KeyMap

    init() {
        if let stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] {
            map = KeyMap(bindings: stored)
        } else {
            map = KeyMap.defaults
            UserDefaults.standard.set(map.bindings, forKey: Self.defaultsKey)
        }
    }

    func assign(_ chord: KeyChord, to command: ActionCommand) {
        map.assign(chord, to: command)
        save()
    }

    func removeBinding(for chord: KeyChord) {
        map.removeBinding(for: chord)
        save()
    }

    func resetToDefaults() {
        map = KeyMap.defaults
        save()
    }

    private func save() {
        UserDefaults.standard.set(map.bindings, forKey: Self.defaultsKey)
    }
}
