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

    public init(bindings: [String: String] = [:]) {
        self.bindings = bindings
    }

    public func command(for key: Key) -> ActionCommand? {
        bindings[key.bindingString].flatMap(ActionCommand.init(actionString:))
    }

    /// The key bound to a command (for menu display) — nil when unbound.
    public func key(for command: ActionCommand) -> Key? {
        let action = command.actionString
        return bindings.first { $0.value == action }
            .flatMap { Key(bindingString: $0.key) }
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
