/// A keyboard chord and its canonical key string (spec §12.1):
/// `[ctrl+][opt+][shift+][cmd+]<key>` — the modifier order is fixed and
/// significant, `<key>` is a lowercased single character or one of the exact
/// PascalCase special names. Case matters in both directions.
public struct KeyChord: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let ctrl = Modifiers(rawValue: 1 << 0)
        public static let opt = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let cmd = Modifiers(rawValue: 1 << 3)
    }

    public static let specialKeys: Set<String> = [
        "UpArrow", "DownArrow", "LeftArrow", "RightArrow",
        "Space", "Escape", "Return", "Delete", "Tab",
    ]

    public let modifiers: Modifiers
    public let key: String

    public init?(modifiers: Modifiers = [], key: String) {
        let isSpecial = Self.specialKeys.contains(key)
        let isPlain = key.count == 1 && key == key.lowercased()
        guard isSpecial || isPlain else { return nil }
        self.modifiers = modifiers
        self.key = key
    }

    public var keyString: String {
        var result = ""
        if modifiers.contains(.ctrl) { result += "ctrl+" }
        if modifiers.contains(.opt) { result += "opt+" }
        if modifiers.contains(.shift) { result += "shift+" }
        if modifiers.contains(.cmd) { result += "cmd+" }
        return result + key
    }

    /// Strict parse — prefixes must appear in the fixed order, so
    /// `cmd+opt+l` is invalid while `opt+cmd+l` parses.
    public init?(keyString: String) {
        var rest = Substring(keyString)
        var modifiers: Modifiers = []
        for (prefix, modifier): (String, Modifiers) in
            [("ctrl+", .ctrl), ("opt+", .opt), ("shift+", .shift), ("cmd+", .cmd)]
        where rest.hasPrefix(prefix) && rest.count > prefix.count {
            modifiers.insert(modifier)
            rest = rest.dropFirst(prefix.count)
        }
        self.init(modifiers: modifiers, key: String(rest))
    }
}
