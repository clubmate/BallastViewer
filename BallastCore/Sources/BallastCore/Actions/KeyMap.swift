extension KeyChord: BindingKey {
    public var bindingString: String { keyString }

    public init?(bindingString: String) {
        self.init(keyString: bindingString)
    }
}

/// The user's shortcut map: canonical key string → action string, exactly the
/// original's persistence model (spec §12.1). See `BindingMap` for the 1:1
/// binding rules (§12.4).
public typealias KeyMap = BindingMap<KeyChord>

extension BindingMap where Key == KeyChord {
    /// The spec §12.3 default map, written on first launch and restored by
    /// Reset Defaults. No defaults exist for `toggleViewMode`, `ratingUp`,
    /// `ratingDown`, or any keyword.
    public static var defaults: KeyMap {
        KeyMap(bindings: [
            "RightArrow": "app:nextPhoto",
            "LeftArrow": "app:previousPhoto",
            "UpArrow": "app:moveUp",
            "DownArrow": "app:moveDown",
            "cmd+a": "app:selectAll",
            "s": "app:focusSearch",
            "k": "app:focusKeywords",
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
    }

    /// The chord bound to a command (for menu display) — nil when unbound.
    public func chord(for command: ActionCommand) -> KeyChord? {
        key(for: command)
    }
}
