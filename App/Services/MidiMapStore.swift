import BallastCore
import Foundation
import Observation

/// The user's MIDI map: persists every change and republishes so LED state and
/// the Settings rows update live. No defaults — the map starts empty, and
/// Reset Defaults clears it entirely (spec §13.1).
@MainActor @Observable
final class MidiMapStore {
    private static let defaultsKey = "midiShortcuts"

    private(set) var map: MidiMap

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String]
        map = MidiMap(bindings: stored ?? [:])
    }

    func assign(_ address: MidiAddress, to command: ActionCommand) {
        map.assign(address, to: command)
        save()
    }

    func removeBinding(for address: MidiAddress) {
        map.removeBinding(for: address)
        save()
    }

    func clearAll() {
        map = MidiMap()
        save()
    }

    private func save() {
        UserDefaults.standard.set(map.bindings, forKey: Self.defaultsKey)
    }
}
