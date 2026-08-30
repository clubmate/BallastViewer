import Testing
@testable import BallastCore

@Suite struct KeyChordTests {
    @Test func keyStringAssemblesModifiersInFixedOrder() {
        let chord = KeyChord(modifiers: [.cmd, .opt, .ctrl, .shift], key: "l")
        #expect(chord?.keyString == "ctrl+opt+shift+cmd+l")
        #expect(KeyChord(modifiers: [.opt, .cmd], key: "l")?.keyString == "opt+cmd+l")
        #expect(KeyChord(key: "5")?.keyString == "5")
        #expect(KeyChord(key: "Space")?.keyString == "Space")
    }

    @Test func parseAcceptsOnlyTheFixedModifierOrder() {
        #expect(KeyChord(keyString: "opt+cmd+l") == KeyChord(modifiers: [.opt, .cmd], key: "l"))
        // Out-of-order modifiers are a different, invalid string (spec §12.1).
        #expect(KeyChord(keyString: "cmd+opt+l") == nil)
        #expect(KeyChord(keyString: "ctrl+opt+shift+cmd+UpArrow") ==
            KeyChord(modifiers: [.ctrl, .opt, .shift, .cmd], key: "UpArrow"))
        #expect(KeyChord(keyString: "5") == KeyChord(key: "5"))
    }

    @Test func caseIsSignificant() {
        // Uppercase single chars are invalid; special names must match exactly.
        #expect(KeyChord(key: "A") == nil)
        // Whitespace is not a plain key — the space bar is spelled "Space".
        #expect(KeyChord(key: " ") == nil)
        #expect(KeyChord(key: "\t") == nil)
        #expect(KeyChord(keyString: "cmd+ ") == nil)
        #expect(KeyChord(keyString: " ") == nil)
        #expect(KeyChord(keyString: "space") == nil)
        #expect(KeyChord(keyString: "Space") != nil)
        #expect(KeyChord(keyString: "UPARROW") == nil)
    }

    @Test func degenerateStringsFailToParse() {
        #expect(KeyChord(keyString: "") == nil)
        #expect(KeyChord(keyString: "cmd+") == nil)
        #expect(KeyChord(keyString: "ab") == nil)
        // "+" itself is a bindable key.
        #expect(KeyChord(keyString: "shift++") == KeyChord(modifiers: [.shift], key: "+"))
    }
}

@Suite struct ActionCommandTests {
    @Test func appNamespaceParsesAllActions() {
        // Spec §12.2's nineteen plus selectAll (U33) and the two focus actions (U39).
        #expect(AppAction.allCases.count == 22)
        for action in AppAction.allCases {
            let command = ActionCommand(actionString: "app:\(action.rawValue)")
            #expect(command == .app(action))
            #expect(command?.actionString == "app:\(action.rawValue)")
        }
    }

    @Test func keywordNamespaceIsVerbatimIncludingSpacesAndSeparators() {
        let command = ActionCommand(actionString: "keyword:PEOPLE > ANNA")
        #expect(command == .keyword("PEOPLE > ANNA"))
        #expect(command?.actionString == "keyword:PEOPLE > ANNA")
        // Not normalised at parse time (C7 is fixed at binding creation, step 9).
        #expect(ActionCommand(actionString: "keyword:anna") == .keyword("anna"))
    }

    @Test func unknownStringsFailToParse() {
        #expect(ActionCommand(actionString: "app:doesNotExist") == nil)
        #expect(ActionCommand(actionString: "keyword:") == nil)
        #expect(ActionCommand(actionString: "rate3") == nil)
        #expect(ActionCommand(actionString: "") == nil)
    }
}

@Suite struct KeyMapTests {
    @Test func initDedupesToOneKeyPerActionDeterministically() {
        let rate = ActionCommand.app(.rate1).actionString
        let map = KeyMap(bindings: ["z": rate, "b": rate, "m": rate, "a": ActionCommand.app(.rate2).actionString])
        #expect(map.bindings == ["b": rate, "a": ActionCommand.app(.rate2).actionString])
        #expect(map.key(for: .app(.rate1)) == KeyChord(key: "b"))
        #expect(map.key(for: .app(.rate2)) == KeyChord(key: "a"))
        #expect(map.key(for: .app(.rate3)) == nil)
    }

    @Test func renameKeywordPathRewritesSubtreeBindings() {
        var map = KeyMap(bindings: [
            "a": ActionCommand.keyword("PEOPLE").actionString,
            "b": ActionCommand.keyword("PEOPLE > ANNA").actionString,
            "c": ActionCommand.keyword("PEOPLEX > BOB").actionString,
            "d": ActionCommand.app(.rate1).actionString,
        ])
        map.renameKeywordPath(from: "PEOPLE", to: "FOLKS")
        #expect(map.bindings["a"] == ActionCommand.keyword("FOLKS").actionString)
        #expect(map.bindings["b"] == ActionCommand.keyword("FOLKS > ANNA").actionString)
        // Prefix match is on whole components — PEOPLEX is untouched.
        #expect(map.bindings["c"] == ActionCommand.keyword("PEOPLEX > BOB").actionString)
        #expect(map.bindings["d"] == ActionCommand.app(.rate1).actionString)
    }

    @Test func defaultsMatchSpec12_3() throws {
        let map = KeyMap.defaults
        // Spec §12.3's sixteen plus cmd+a (U33) and s/k (U39).
        #expect(map.bindings.count == 19)
        let expectations: [(String, AppAction)] = [
            ("RightArrow", .nextPhoto), ("LeftArrow", .previousPhoto),
            ("UpArrow", .moveUp), ("DownArrow", .moveDown),
            ("Space", .rotate), ("Escape", .viewGrid), ("Return", .viewSingle),
            ("0", .rate0), ("1", .rate1), ("2", .rate2),
            ("3", .rate3), ("4", .rate4), ("5", .rate5),
            ("opt+cmd+l", .toggleLeftPanel),
            ("opt+cmd+r", .toggleRightPanel),
            ("opt+cmd+b", .toggleBottomPanel),
        ]
        for (keyString, action) in expectations {
            let chord = try #require(KeyChord(keyString: keyString))
            #expect(map.command(for: chord) == .app(action))
        }
        // Deliberately unbound by default (spec §12.3).
        #expect(map.chord(for: .app(.toggleViewMode)) == nil)
        #expect(map.chord(for: .app(.ratingUp)) == nil)
        #expect(map.chord(for: .app(.ratingDown)) == nil)
    }

    @Test func assignIsOneToOneInBothDirections() throws {
        var map = KeyMap.defaults
        let space = try #require(KeyChord(keyString: "Space"))
        // Rebinding Space steals it from rotate…
        map.assign(space, to: .app(.toggleViewMode))
        #expect(map.command(for: space) == .app(.toggleViewMode))
        #expect(map.chord(for: .app(.rotate)) == nil)
        // …and giving toggleViewMode a new key removes Space again.
        let t = try #require(KeyChord(keyString: "t"))
        map.assign(t, to: .app(.toggleViewMode))
        #expect(map.command(for: t) == .app(.toggleViewMode))
        #expect(map.command(for: space) == nil)
    }

    @Test func keywordCommandsAreBindable() throws {
        var map = KeyMap()
        let a = try #require(KeyChord(keyString: "a"))
        map.assign(a, to: .keyword("PEOPLE > ANNA"))
        #expect(map.command(for: a) == .keyword("PEOPLE > ANNA"))
        #expect(map.chord(for: .keyword("PEOPLE > ANNA")) == a)
    }
}
