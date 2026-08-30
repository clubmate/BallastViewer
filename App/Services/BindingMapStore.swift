import BallastCore
import Foundation
import Observation

/// Defaults-backed owner of one `BindingMap`: persists every change and
/// republishes so menus, LED state and the Settings rows update live.
/// `KeyMapStore` and `MidiMapStore` are this one implementation over their
/// key types — they differ only in the defaults key and the reset value.
@MainActor @Observable
final class BindingMapStore<Key: BindingKey> {
    private let defaultsKey: String
    /// What Reset Defaults restores — the spec §12.3 keyboard defaults, or an
    /// empty map for MIDI (spec §13.1).
    private let resetValue: BindingMap<Key>

    private(set) var map: BindingMap<Key>

    /// Loads the stored map; when nothing is stored yet, `initial` is written
    /// (so a first launch persists the keyboard defaults, spec §12.3).
    init(defaultsKey: String, initial: BindingMap<Key>, resetValue: BindingMap<Key>) {
        self.defaultsKey = defaultsKey
        self.resetValue = resetValue
        if let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] {
            map = BindingMap(bindings: stored)
        } else {
            map = initial
            UserDefaults.standard.set(initial.bindings, forKey: defaultsKey)
        }
    }

    func assign(_ key: Key, to command: ActionCommand) {
        map.assign(key, to: command)
        save()
    }

    func removeBinding(for key: Key) {
        map.removeBinding(for: key)
        save()
    }

    func reset() {
        map = resetValue
        save()
    }

    /// One-time adoption of a default binding added in a later app version —
    /// stored maps predate it and would otherwise never receive it. Applied
    /// only when neither the key nor the action is already bound, and never
    /// again after the first attempt (`marker`): a user remap or a deliberate
    /// unbind must not be fought on every launch.
    func adoptDefaultOnce(key keyString: String, action actionString: String, marker: String) {
        guard !UserDefaults.standard.bool(forKey: marker) else { return }
        UserDefaults.standard.set(true, forKey: marker)
        var bindings = map.bindings
        guard bindings[keyString] == nil, !bindings.values.contains(actionString) else { return }
        bindings[keyString] = actionString
        map = BindingMap(bindings: bindings)
        save()
    }

    /// Follows a vocabulary rename so keyword bindings (and their LEDs) stay live.
    func renameKeywordPath(from oldPath: String, to newPath: String) {
        map.renameKeywordPath(from: oldPath, to: newPath)
        save()
    }

    private func save() {
        UserDefaults.standard.set(map.bindings, forKey: defaultsKey)
    }
}

/// The user's key map: writes the spec §12.3 defaults on first launch.
typealias KeyMapStore = BindingMapStore<KeyChord>

extension BindingMapStore where Key == KeyChord {
    convenience init() {
        self.init(defaultsKey: "keyboardShortcuts", initial: KeyMap.defaults, resetValue: KeyMap.defaults)
        // U33/U39 shipped after the first stored maps existed.
        adoptDefaultOnce(key: "cmd+a", action: "app:selectAll", marker: "adopted.cmd+a.selectAll")
        adoptDefaultOnce(key: "s", action: "app:focusSearch", marker: "adopted.s.focusSearch")
        adoptDefaultOnce(key: "k", action: "app:focusKeywords", marker: "adopted.k.focusKeywords")
    }

    func resetToDefaults() { reset() }
}

/// The user's MIDI map: no defaults — it starts empty, and Reset Defaults
/// clears it entirely (spec §13.1).
typealias MidiMapStore = BindingMapStore<MidiAddress>

extension BindingMapStore where Key == MidiAddress {
    convenience init() {
        self.init(defaultsKey: "midiShortcuts", initial: MidiMap(), resetValue: MidiMap())
    }

    func clearAll() { reset() }
}
