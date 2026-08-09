import BallastCore
import CoreMIDI
import Foundation
import Observation

/// The CoreMIDI bridge (spec §13): connects every source (with hot-plug, C10),
/// parses input through the length-based core parser (C9), dispatches through
/// the shared ActionDispatcher with per-action debounce (§13.4), and drives
/// pad LEDs — on = NoteOn velocity 127, off = NoteOn velocity 0, re-asserted
/// on every Note Off (Q3, §13.7).
@MainActor @Observable
final class MidiService {
    @ObservationIgnored private let midiMap: MidiMapStore
    @ObservationIgnored private let appearance: AppearanceStore
    @ObservationIgnored private let dispatcher: ActionDispatcher
    @ObservationIgnored private let center: CenterViewModel

    /// Recorder capture (spec §13.8): while armed, the next Note On lands here
    /// instead of dispatching.
    var captureHandler: (@MainActor (MidiAddress) -> Void)?
    /// Output destinations for the Appearance picker.
    private(set) var destinationNames: [String] = []
    /// Resolved endpoints, refreshed on hot-plug — `send` must not enumerate
    /// and re-resolve display names per LED update.
    @ObservationIgnored private var destinations: [(endpoint: MIDIEndpointRef, name: String)] = []

    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var inputPort = MIDIPortRef()
    @ObservationIgnored private var outputPort = MIDIPortRef()
    @ObservationIgnored private var connectedSources: Set<MIDIEndpointRef> = []
    /// Per-action debounce timestamps (§13.4: per action, not per note).
    @ObservationIgnored private var lastDispatch: [String: Date] = [:]
    /// Last LED state sent, for diffing and Q3 re-asserts.
    @ObservationIgnored private var litAddresses: Set<MidiAddress> = []

    init(
        midiMap: MidiMapStore,
        appearance: AppearanceStore,
        dispatcher: ActionDispatcher,
        center: CenterViewModel
    ) {
        self.midiMap = midiMap
        self.appearance = appearance
        self.dispatcher = dispatcher
        self.center = center
        setUpClient()
        connectSources()
        refreshDestinations()
        observeAndApplyLEDState()
        resendFullLEDState()
    }

    // MARK: CoreMIDI setup

    private func setUpClient() {
        // Hot-plug (C10): the notify block fires on setup changes — reconnect
        // new sources, refresh the destination list, and re-light new devices.
        // Same explicit @Sendable rule as the receiver below.
        let notify: @Sendable (UnsafePointer<MIDINotification>) -> Void = { [weak self] pointer in
            guard pointer.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.connectSources()
                    self.refreshDestinations()
                    self.resendFullLEDState()
                }
            }
        }
        MIDIClientCreateWithBlock("ballastviewer" as CFString, &client, notify)
        // Input uses the protocol API (the legacy packet-list input port stops
        // receiving on current macOS); events arrive as MIDI-1.0-in-UMP words
        // and are flattened back to a plain byte stream for the core parser.
        //
        // The block MUST be explicitly @Sendable: formed inside a @MainActor
        // method it would otherwise inherit main-actor isolation, and CoreMIDI
        // invokes it on its own thread — the runtime isolation assert then
        // kills the app on the first incoming event.
        let receiver: @Sendable (UnsafePointer<MIDIEventList>, UnsafeMutableRawPointer?) -> Void =
            { [weak self] eventListPointer, _ in
                let packets = Self.byteArrays(from: eventListPointer)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.handle(packets: packets)
                    }
                }
            }
        let inputStatus = MIDIInputPortCreateWithProtocol(
            client, "input" as CFString, ._1_0, &inputPort, receiver
        )
        let outputStatus = MIDIOutputPortCreate(client, "output" as CFString, &outputPort)
        debugLog("ports input=\(inputStatus) output=\(outputStatus) port=\(inputPort)")
    }

    private func connectSources() {
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            guard source != 0, !connectedSources.contains(source) else { continue }
            let status = MIDIPortConnectSource(inputPort, source, nil)
            if status == noErr {
                connectedSources.insert(source)
            }
            debugLog("connect source=\(Self.displayName(of: source) ?? "?") status=\(status)")
        }
    }

    /// Diagnostics for the headless MIDI test hook; inert otherwise.
    private func debugLog(_ message: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BV_TEST_MIDI"] != nil {
            print("BVMIDI svc \(message)")
        }
        #endif
    }

    private func refreshDestinations() {
        destinations = (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0, let name = Self.displayName(of: endpoint) else { return nil }
            return (endpoint, name)
        }
        destinationNames = destinations.map(\.name)
    }

    nonisolated private static func displayName(of endpoint: MIDIEndpointRef) -> String? {
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr
        else { return nil }
        return name?.takeRetainedValue() as String?
    }

    /// Flattens MIDI-1.0-in-UMP event packets back into byte streams. Channel
    /// voice words (message type 2) carry status + two data bytes; two-byte
    /// messages (program change, channel pressure) drop the padding byte so
    /// the length-based parser sees exactly the wire format.
    nonisolated private static func byteArrays(
        from eventList: UnsafePointer<MIDIEventList>
    ) -> [[UInt8]] {
        var packets: [[UInt8]] = []
        var packet = eventList.pointee.packet
        for _ in 0..<eventList.pointee.numPackets {
            let wordCount = Int(packet.wordCount)
            let words = withUnsafeBytes(of: packet.words) { raw in
                Array(raw.bindMemory(to: UInt32.self).prefix(wordCount))
            }
            var bytes: [UInt8] = []
            for word in words where word >> 28 == 0x2 {
                let status = UInt8((word >> 16) & 0xFF)
                bytes.append(status)
                bytes.append(UInt8((word >> 8) & 0x7F))
                if (status & 0xF0) != 0xC0, (status & 0xF0) != 0xD0 {
                    bytes.append(UInt8(word & 0x7F))
                }
            }
            if !bytes.isEmpty {
                packets.append(bytes)
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
        return packets
    }

    // MARK: Input

    private func handle(packets: [[UInt8]]) {
        for bytes in packets {
            debugLog("recv \(bytes.map { String($0) }.joined(separator: ","))")
            for event in MidiParser.parse(bytes) {
                handle(event)
            }
        }
    }

    private func handle(_ event: MidiNoteEvent) {
        switch event {
        case .on(let address, _):
            if let captureHandler {
                // Recorder armed: capture instead of dispatching (§13.8).
                captureHandler(address)
                return
            }
            guard let command = midiMap.map.command(for: address) else { return }
            let debounceMs = appearance.midiDebounceMs
            if debounceMs > 0 {
                let key = command.actionString
                let now = Date()
                if let last = lastDispatch[key],
                   now.timeIntervalSince(last) * 1000 < Double(debounceMs) {
                    return
                }
                lastDispatch[key] = now
            }
            dispatcher.dispatch(command, source: .midi)
        case .off(let address):
            // Q3: many controllers extinguish a released pad themselves —
            // immediately re-send its correct state so lit pads stay lit.
            guard midiMap.map.bindings[address.noteString] != nil else { return }
            send(address, on: litAddresses.contains(address))
        }
    }

    // MARK: LED feedback (§13.6)

    /// Re-applies LED state now and again whenever the control surface or the
    /// MIDI map changes (Observation tracking).
    private func observeAndApplyLEDState() {
        withObservationTracking {
            applyLEDState()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeAndApplyLEDState()
            }
        }
    }

    private func applyLEDState() {
        let lit = LEDStateComputer.litAddresses(map: midiMap.map, state: center.controlSurface)
        for address in lit.subtracting(litAddresses) { send(address, on: true) }
        for address in litAddresses.subtracting(lit) { send(address, on: false) }
        litAddresses = lit
    }

    /// Explicit on/off for every bound pad — startup and hot-plug, so a newly
    /// attached controller shows the current state immediately.
    private func resendFullLEDState() {
        litAddresses = LEDStateComputer.litAddresses(
            map: midiMap.map, state: center.controlSurface
        )
        for noteString in midiMap.map.bindings.keys {
            guard let address = MidiAddress(noteString: noteString) else { continue }
            send(address, on: litAddresses.contains(address))
        }
    }

    // MARK: Output

    /// On = NoteOn velocity 127, off = NoteOn velocity 0 (§13.6 transport).
    /// Sent to the selected destination, or all of them (the default).
    private func send(_ address: MidiAddress, on: Bool) {
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        let data: [UInt8] = [0x90 | address.channel, address.note, on ? 127 : 0]
        _ = MIDIPacketListAdd(
            &packetList, MemoryLayout<MIDIPacketList>.size, packet, 0, data.count, data
        )
        let selected = appearance.midiOutputDestination
        for destination in destinations {
            if !selected.isEmpty, destination.name != selected { continue }
            MIDISend(outputPort, destination.endpoint, &packetList)
        }
    }
}
