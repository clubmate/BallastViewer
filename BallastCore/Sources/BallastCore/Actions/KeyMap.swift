/// The user's shortcut map: canonical key string → action string, exactly the
/// original's persistence model (spec §12.1). Binding is strictly 1:1 in both
/// directions (§12.4) — the conflict *warning* is the step-9 editor's job (U11),
/// the map itself always ends up consistent.
public struct KeyMap: Equatable, Sendable {
    public private(set) var bindings: [String: String]

    public init(bindings: [String: String] = [:]) {
        self.bindings = bindings
    }

    /// The spec §12.3 default map, written on first launch and restored by
    /// Reset Defaults. No defaults exist for `toggleViewMode`, `ratingUp`,
    /// `ratingDown`, or any keyword.
    public static let defaults = KeyMap(bindings: [
        "RightArrow": "app:nextPhoto",
        "LeftArrow": "app:previousPhoto",
        "UpArrow": "app:moveUp",
        "DownArrow": "app:moveDown",
        "Space": "app:rotate",
        "Escape": "app:viewGrid",
        "Return": "app:viewSingle",
        "0": "app:rate0",
        "1": "app:rate1",
        "2": "app:rate2",
        "3": "app:rate3",
        "4": "app:rate4",
        "5": "app:rate5",
        "opt+cmd+l": "app:toggleLeftPanel",
        "opt+cmd+r": "app:toggleRightPanel",
        "opt+cmd+b": "app:toggleBottomPanel",
    ])

    public func command(for chord: KeyChord) -> ActionCommand? {
        bindings[chord.keyString].flatMap(ActionCommand.init(actionString:))
    }

    /// The chord bound to a command (for menu display) — nil when unbound.
    public func chord(for command: ActionCommand) -> KeyChord? {
        let action = command.actionString
        return bindings.first { $0.value == action }
            .flatMap { KeyChord(keyString: $0.key) }
    }

    /// Spec §12.4: assigning K → A first removes any existing binding of K,
    /// then every other key bound to A.
    public mutating func assign(_ chord: KeyChord, to command: ActionCommand) {
        let action = command.actionString
        bindings = bindings.filter { $0.value != action }
        bindings[chord.keyString] = action
    }

    public mutating func removeBinding(for chord: KeyChord) {
        bindings[chord.keyString] = nil
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
