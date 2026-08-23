import Testing
@testable import BallastCore

struct MidiAddressTests {
    @Test func codecRoundTripsAndValidates() {
        let address = MidiAddress(channel: 0, note: 60)!
        #expect(address.noteString == "note:0:60")
        #expect(MidiAddress(noteString: "note:0:60") == address)
        #expect(address.displayName == "CH1 N:60")
        #expect(MidiAddress(noteString: "note:16:60") == nil)
        #expect(MidiAddress(noteString: "note:0:128") == nil)
        #expect(MidiAddress(noteString: "key:0:60") == nil)
        #expect(MidiAddress(channel: 15, note: 127)?.displayName == "CH16 N:127")
    }
}

struct MidiMapTests {
    @Test func bindingIsStrictlyOneToOne() {
        var map = MidiMap()
        let pad1 = MidiAddress(channel: 0, note: 60)!
        let pad2 = MidiAddress(channel: 0, note: 61)!
        map.assign(pad1, to: .app(.rate3))
        map.assign(pad2, to: .app(.rate3))
        // The action's previous note is gone; the new one resolves.
        #expect(map.command(for: pad1) == nil)
        #expect(map.command(for: pad2) == .app(.rate3))
        map.assign(pad2, to: .keyword("PEOPLE > ANNA"))
        // The note's previous action is gone.
        #expect(map.command(for: pad2) == .keyword("PEOPLE > ANNA"))
        #expect(map.address(for: .app(.rate3)) == nil)
    }
}

struct MidiParserTests {
    private func on(_ note: UInt8, velocity: UInt8 = 100) -> MidiNoteEvent {
        .on(MidiAddress(channel: 0, note: note)!, velocity: velocity)
    }

    @Test func parsesNoteOnAndOff() {
        let events = MidiParser.parse([0x90, 60, 100, 0x80, 60, 0])
        #expect(events == [on(60), .off(MidiAddress(channel: 0, note: 60)!)])
    }

    @Test func velocityZeroIsNoteOff() {
        #expect(MidiParser.parse([0x90, 60, 0]) == [.off(MidiAddress(channel: 0, note: 60)!)])
    }

    @Test func channelIsExtractedFromStatus() {
        let events = MidiParser.parse([0x9A, 40, 1])
        #expect(events == [.on(MidiAddress(channel: 10, note: 40)!, velocity: 1)])
    }

    @Test func controlChangeIsSkippedWhole() {
        // CC (3 bytes) directly followed by a note: exactly one event.
        let events = MidiParser.parse([0xB0, 7, 100, 0x90, 60, 100])
        #expect(events == [on(60)])
    }

    @Test func programChangeConsumesTwoBytes() {
        let events = MidiParser.parse([0xC0, 5, 0x90, 60, 100])
        #expect(events == [on(60)])
    }

    @Test func sysexNeverFabricatesPhantomNotes() {
        // C9 regression: a malformed SysEx containing 0x90-lookalike bytes must
        // not produce a note — everything until 0xF7 is data.
        let events = MidiParser.parse([0xF0, 0x01, 0x90, 60, 100, 0xF7, 0x90, 61, 100])
        #expect(events == [on(61)])
    }

    @Test func interleavedRealtimeBytesAreTransparent() {
        // Clock (0xF8) and active sensing (0xFE) may sit between the data
        // bytes of a channel message; they are neither data nor a new status.
        let events = MidiParser.parse([0x90, 0xFE, 60, 0xF8, 100, 0xFE, 0x80, 60, 0xF8, 0])
        #expect(events == [on(60), .off(MidiAddress(channel: 0, note: 60)!)])
    }

    @Test func runningStatusReusesLastChannelStatus() {
        // Two notes, the second without a repeated 0x90.
        let events = MidiParser.parse([0x90, 60, 100, 61, 90])
        #expect(events == [on(60), on(61, velocity: 90)])
        // A CC in between takes over running status; stray data after SysEx
        // (which clears it) is ignored.
        let mixed = MidiParser.parse([0x90, 60, 100, 0xB0, 7, 1, 7, 2, 0xF0, 1, 0xF7, 62, 5, 0x90, 63, 4])
        #expect(mixed == [on(60), on(63, velocity: 4)])
    }

    @Test func pitchBendAndAftertouchAreSkipped() {
        let events = MidiParser.parse([0xE0, 0, 64, 0xD0, 50, 0xA0, 60, 10, 0x90, 62, 9])
        #expect(events == [on(62, velocity: 9)])
    }

    @Test func truncatedTrailingMessageIsDropped() {
        #expect(MidiParser.parse([0x90, 60]) == [])
        #expect(MidiParser.parse([0x90]) == [])
    }

    @Test func strayDataBytesAreIgnored() {
        #expect(MidiParser.parse([12, 34, 0x90, 60, 100]) == [on(60)])
    }

    /// A status byte where data was expected ends the truncated message and
    /// starts a new one — it is never consumed as a velocity (which would
    /// have produced velocity 144 and swallowed the real note).
    @Test func statusByteInDataPositionRestartsParsing() {
        let events = MidiParser.parse([0x90, 0x3C, 0x90, 0x3C, 0x40])
        #expect(events == [on(60, velocity: 64)])
        for case .on(_, let velocity) in events {
            #expect(velocity < 128)
        }
    }
}

struct LEDStateComputerTests {
    private let anna = "PEOPLE > ANNA"

    @Test func starsLightCumulativelyAndRateZeroIsExact() {
        let rated4 = ControlSurfaceState(anchorRating: 4)
        #expect(LEDStateComputer.isLit(.app(.rate1), state: rated4))
        #expect(LEDStateComputer.isLit(.app(.rate4), state: rated4))
        #expect(!LEDStateComputer.isLit(.app(.rate5), state: rated4))
        #expect(!LEDStateComputer.isLit(.app(.rate0), state: rated4))

        let unrated = ControlSurfaceState(anchorRating: 0)
        #expect(LEDStateComputer.isLit(.app(.rate0), state: unrated))
        #expect(!LEDStateComputer.isLit(.app(.rate1), state: unrated))
    }

    @Test func viewModePads() {
        let grid = ControlSurfaceState(isSingleView: false)
        let single = ControlSurfaceState(isSingleView: true)
        #expect(LEDStateComputer.isLit(.app(.viewGrid), state: grid))
        #expect(!LEDStateComputer.isLit(.app(.viewSingle), state: grid))
        #expect(!LEDStateComputer.isLit(.app(.toggleViewMode), state: grid))
        #expect(LEDStateComputer.isLit(.app(.viewSingle), state: single))
        #expect(LEDStateComputer.isLit(.app(.toggleViewMode), state: single))
        #expect(!LEDStateComputer.isLit(.app(.viewGrid), state: single))
    }

    @Test func keywordPadsMatchExactly() {
        let state = ControlSurfaceState(anchorKeywords: [anna])
        #expect(LEDStateComputer.isLit(.keyword(anna), state: state))
        #expect(!LEDStateComputer.isLit(.keyword("ANNA"), state: state))
        #expect(!LEDStateComputer.isLit(.keyword(anna), state: ControlSurfaceState()))
    }

    @Test func navigationStaysDark() {
        let state = ControlSurfaceState(anchorRating: 5, isSingleView: true)
        for action in [AppAction.nextPhoto, .previousPhoto, .moveUp, .moveDown,
                       .rotate, .ratingUp, .ratingDown,
                       .toggleLeftPanel, .toggleRightPanel, .toggleBottomPanel] {
            #expect(!LEDStateComputer.isLit(.app(action), state: state))
        }
    }

    @Test func litAddressesFiltersBoundPads() {
        var map = MidiMap()
        map.assign(MidiAddress(channel: 0, note: 60)!, to: .app(.rate1))
        map.assign(MidiAddress(channel: 0, note: 61)!, to: .app(.rate5))
        map.assign(MidiAddress(channel: 0, note: 62)!, to: .keyword(anna))
        map.assign(MidiAddress(channel: 0, note: 63)!, to: .app(.nextPhoto))
        let state = ControlSurfaceState(anchorKeywords: [anna], anchorRating: 2)
        let lit = LEDStateComputer.litAddresses(parsed: LEDStateComputer.parseBindings(map), state: state)
        #expect(lit == [MidiAddress(channel: 0, note: 60)!, MidiAddress(channel: 0, note: 62)!])
    }
}
