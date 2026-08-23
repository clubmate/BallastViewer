/// A key identity that round-trips through the map's persisted string form
/// (`"opt+cmd+l"`, `"note:0:60"`).
public protocol BindingKey: Sendable {
    var bindingString: String { get }
    init?(bindingString: String)
}

/// A shortcut map: persisted key string → action string, the original's
/// persistence model for both keyboard (§12.1) and MIDI (§13.1). Binding is
/// strictly 1:1 in both directions (§12.4) — the conflict *warning* is the
/// editor's job (U11), the map itself always ends up consistent. `KeyMap` and
/// `MidiMap` are this one implementation over their respective key types.
public struct BindingMap<Key: BindingKey>: Equatable, Sendable {
    public private(set) var bindings: [String: String]

    /// Persisted maps may carry the same action under several keys (older
    /// versions, hand edits); the 1:1 invariant is restored here by keeping,
    /// per action, the smallest binding string — deterministic across loads.
    public init(bindings: [String: String] = [:]) {
        var keyByAction: [String: String] = [:]
        for (key, action) in bindings {
            if let existing = keyByAction[action], existing <= key { continue }
            keyByAction[action] = key
        }
        self.bindings = Dictionary(uniqueKeysWithValues: keyByAction.map { ($0.value, $0.key) })
    }

    public func command(for key: Key) -> ActionCommand? {
        bindings[key.bindingString].flatMap(ActionCommand.init(actionString:))
    }

    /// The key bound to a command (for menu display) — nil when unbound.
    public func key(for command: ActionCommand) -> Key? {
        let action = command.actionString
        // The map is 1:1, but pick the minimum anyway so the answer never
        // depends on dictionary iteration order.
        return bindings.lazy.filter { $0.value == action }.map(\.key).min()
            .flatMap { Key(bindingString: $0) }
    }

    /// Spec §12.4: assigning K → A first removes any existing binding of K,
    /// then every other key bound to A.
    public mutating func assign(_ key: Key, to command: ActionCommand) {
        let action = command.actionString
        bindings = bindings.filter { $0.value != action }
        bindings[key.bindingString] = action
    }

    public mutating func removeBinding(for key: Key) {
        bindings[key.bindingString] = nil
    }

    /// Rewrites keyword bindings after a vocabulary rename (see
    /// `ActionCommand.renamingKeywordPath`) so bindings follow the keyword
    /// instead of going stale.
    public mutating func renameKeywordPath(from oldPath: String, to newPath: String) {
        for (key, actionString) in bindings {
            guard let command = ActionCommand(actionString: actionString),
                  let updated = command.renamingKeywordPath(from: oldPath, to: newPath)
            else { continue }
            bindings[key] = updated.actionString
        }
    }
}
