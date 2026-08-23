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

extension MidiAddress: BindingKey {
    public var bindingString: String { noteString }

    public init?(bindingString: String) {
        self.init(noteString: bindingString)
    }
}

/// The MIDI shortcut map: note string → action string, same persistence model
/// and strict 1:1 binding rules as `KeyMap` (§13.1) — one `BindingMap`
/// implementation. There are no defaults — the map starts empty and *Reset
/// Defaults* clears it entirely.
public typealias MidiMap = BindingMap<MidiAddress>

extension BindingMap where Key == MidiAddress {
    public func address(for command: ActionCommand) -> MidiAddress? {
        key(for: command)
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
///
/// Two wire-level conventions are honoured as well: single-byte realtime
/// messages (0xF8…0xFF — clock, active sensing) may be interleaved *between
/// the data bytes* of any channel message and are skipped transparently, and
/// running status (data bytes without a repeated status byte) reuses the last
/// channel status.
public enum MidiParser {
    public static func parse(_ bytes: [UInt8]) -> [MidiNoteEvent] {
        var events: [MidiNoteEvent] = []
        var index = 0
        var runningStatus: UInt8? = nil

        /// Next data byte at or after `index`, advancing past it (realtime
        /// bytes are skipped). nil when the stream ends — or when a status
        /// byte appears where data was expected (a truncated message); then
        /// `index` is left pointing at that status byte so the outer loop
        /// parses it instead of swallowing it as a velocity or note.
        func nextData() -> UInt8? {
            while index < bytes.count {
                let byte = bytes[index]
                if byte >= 0xF8 { index += 1; continue }
                if byte >= 0x80 { return nil }
                index += 1
                return byte
            }
            return nil
        }

        while index < bytes.count {
            var status = bytes[index]
            if status >= 0xF8 {
                index += 1  // realtime: never alters running status
                continue
            }
            if status < 0x80 {
                // Data byte in status position → running status, if any.
                guard let running = runningStatus else { index += 1; continue }
                status = running
            } else {
                index += 1
                // System common/exclusive clears running status; channel
                // messages set it.
                runningStatus = status < 0xF0 ? status : nil
            }

            switch status {
            case 0x80...0x9F:
                // Truncated note message: drop it and resume at the status
                // byte that cut it short.
                guard let note = nextData(), let velocity = nextData() else { continue }
                let channel = status & 0x0F
                if let address = MidiAddress(channel: channel, note: note) {
                    let isOn = status >= 0x90 && velocity > 0
                    events.append(isOn ? .on(address, velocity: velocity) : .off(address))
                }
            case 0xA0...0xBF, 0xE0...0xEF:
                // Poly aftertouch, control change, pitch bend: 2 data bytes.
                _ = nextData(); _ = nextData()
            case 0xC0...0xDF:
                // Program change, channel aftertouch: 1 data byte.
                _ = nextData()
            case 0xF0:
                // SysEx: consume through the terminating 0xF7 — embedded bytes
                // are data, never status (the phantom-note fix).
                while index < bytes.count, bytes[index] != 0xF7 { index += 1 }
                index += 1
            case 0xF1, 0xF3:
                _ = nextData()
            case 0xF2:
                _ = nextData(); _ = nextData()
            default:
                // Remaining system common messages: no data.
                break
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
}
