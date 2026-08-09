/// A MIDI note identity (spec §13.1): channel is **0-based** (0–15) as on the
/// wire, note 0–127. Persisted as `note:<channel>:<note>`, displayed 1-based
/// as `CH<channel+1> N:<note>`.
public struct MidiAddress: Hashable, Sendable {
    public var channel: UInt8
    public var note: UInt8

    public init?(channel: UInt8, note: UInt8) {
        guard channel <= 15, note <= 127 else { return nil }
        self.channel = channel
        self.note = note
    }

    public var noteString: String {
        "note:\(channel):\(note)"
    }

    public init?(noteString: String) {
        let parts = noteString.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "note",
              let channel = UInt8(parts[1]), let note = UInt8(parts[2])
        else { return nil }
        self.init(channel: channel, note: note)
    }

    /// UI form, 1-based channel (spec §13.1).
    public var displayName: String {
        "CH\(channel + 1) N:\(note)"
    }
}

/// The MIDI shortcut map: note string → action string, same persistence model
/// and strict 1:1 binding rules as `KeyMap` (§13.1). There are no defaults —
/// the map starts empty and *Reset Defaults* clears it entirely.
public struct MidiMap: Equatable, Sendable {
    public private(set) var bindings: [String: String]

    public init(bindings: [String: String] = [:]) {
        self.bindings = bindings
    }

    public func command(for address: MidiAddress) -> ActionCommand? {
        bindings[address.noteString].flatMap(ActionCommand.init(actionString:))
    }

    public func address(for command: ActionCommand) -> MidiAddress? {
        let action = command.actionString
        return bindings.first { $0.value == action }
            .flatMap { MidiAddress(noteString: $0.key) }
    }

    public mutating func assign(_ address: MidiAddress, to command: ActionCommand) {
        let action = command.actionString
        bindings = bindings.filter { $0.value != action }
        bindings[address.noteString] = action
    }

    public mutating func removeBinding(for address: MidiAddress) {
        bindings[address.noteString] = nil
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

/// A note event after velocity folding: Note On with velocity 0 is a Note Off
/// (the running-status convention, spec §13.3).
public enum MidiNoteEvent: Equatable, Sendable {
    case on(MidiAddress, velocity: UInt8)
    case off(MidiAddress)

    public var address: MidiAddress {
        switch self {
        case .on(let address, _), .off(let address): address
        }
    }
}

/// Length-based MIDI byte-stream parser (fixes C9): every message is consumed
/// with its full defined length, so a Control Change's data bytes are never
/// re-examined as potential status bytes and can't fabricate phantom notes.
/// Only note on/off produce events; everything else is skipped whole.
public enum MidiParser {
    public static func parse(_ bytes: [UInt8]) -> [MidiNoteEvent] {
        var events: [MidiNoteEvent] = []
        var index = 0
        while index < bytes.count {
            let status = bytes[index]
            switch status {
            case 0x80...0x8F, 0x90...0x9F:
                guard index + 2 < bytes.count else { return events }
                let channel = status & 0x0F
                let note = bytes[index + 1]
                let velocity = bytes[index + 2]
                if let address = MidiAddress(channel: channel, note: note) {
                    let isOn = status >= 0x90 && velocity > 0
                    events.append(isOn ? .on(address, velocity: velocity) : .off(address))
                }
                index += 3
            case 0xA0...0xBF, 0xE0...0xEF:
                // Poly aftertouch, control change, pitch bend: 3 bytes.
                index += 3
            case 0xC0...0xDF:
                // Program change, channel aftertouch: 2 bytes.
                index += 2
            case 0xF0:
                // SysEx: consume through the terminating 0xF7 — embedded bytes
                // are data, never status (the phantom-note fix).
                index += 1
                while index < bytes.count, bytes[index] != 0xF7 { index += 1 }
                index += 1
            case 0xF1, 0xF3:
                index += 2
            case 0xF2:
                index += 3
            default:
                // Remaining system/realtime messages and stray data bytes.
                index += 1
            }
        }
        return events
    }
}

/// The §13.6 lighting rules. Pure — the app's MIDI service diffs consecutive
/// results and re-asserts single pads on Note Off (Q3).
public enum LEDStateComputer {
    /// Whether the pad bound to `command` is lit for the given surface state.
    public static func isLit(_ command: ActionCommand, state: ControlSurfaceState) -> Bool {
        switch command {
        case .keyword(let text):
            return state.anchorKeywords.contains(text)
        case .app(.rate0):
            // Exact zero — reads as "unrated", not "at least zero" (Q4).
            return state.anchorRating == 0
        case .app(let action):
            if let stars = action.absoluteRating {
                // Cumulative star meter: rating 4 lights pads 1–4 (Q4).
                return state.anchorRating >= stars
            }
            switch action {
            case .viewGrid: return !state.isSingleView
            case .viewSingle, .toggleViewMode: return state.isSingleView
            default: return false  // navigation/rotate/panels stay dark
            }
        }
    }

    /// Bindings parsed out of their string form once — LED updates fire per
    /// anchor change and should not re-parse every binding each time.
    public static func parseBindings(_ map: MidiMap) -> [(address: MidiAddress, command: ActionCommand)] {
        map.bindings.compactMap { noteString, actionString in
            guard let address = MidiAddress(noteString: noteString),
                  let command = ActionCommand(actionString: actionString)
            else { return nil }
            return (address, command)
        }
    }

    /// All bound addresses that must currently be lit, from pre-parsed bindings.
    public static func litAddresses(
        parsed: [(address: MidiAddress, command: ActionCommand)], state: ControlSurfaceState
    ) -> Set<MidiAddress> {
        Set(parsed.compactMap { isLit($0.command, state: state) ? $0.address : nil })
    }

    /// All bound addresses that must currently be lit.
    public static func litAddresses(map: MidiMap, state: ControlSurfaceState) -> Set<MidiAddress> {
        Set(map.bindings.compactMap { noteString, actionString in
            guard let address = MidiAddress(noteString: noteString),
                  let command = ActionCommand(actionString: actionString),
                  isLit(command, state: state)
            else { return nil }
            return address
        })
    }
}
