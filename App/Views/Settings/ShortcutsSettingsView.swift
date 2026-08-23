import BallastCore
import SwiftUI

/// Settings ▸ Shortcuts (spec §9.9): one recorder row per app action, keyword
/// shortcut rows with an add row, Reset Defaults. Binding stays strictly 1:1
/// (§12.4) but overwrites are announced inline instead of silent (U11).
/// MIDI recorders join these rows in step 11.
struct ShortcutsSettingsView: View {
    @Environment(LibraryController.self) private var controller
    @Environment(KeyMapStore.self) private var keyMap
    @Environment(MidiMapStore.self) private var midiMap

    /// U11: per-row "was: …" hint, keyed by the row's action string.
    @State private var conflictHints: [String: String] = [:]
    @State private var newKeywordName = ""
    @State private var newKeywordChord: KeyChord?
    @State private var newKeywordAddress: MidiAddress?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Application Shortcuts") {
                    ForEach(AppAction.allCases, id: \.self) { action in
                        recorderRow(
                            title: Text(action.displayName),
                            command: .app(action)
                        )
                    }
                }
                Section("Keyword Shortcuts") {
                    ForEach(keywordBindings, id: \.keyword) { binding in
                        keywordRow(binding)
                    }
                    addKeywordRow
                }
            }
            .formStyle(.grouped)
            footer
        }
    }

    // MARK: Rows

    private func recorderRow(title: Text, command: ActionCommand) -> some View {
        HStack {
            title
            Spacer()
            if let hint = conflictHints[command.actionString] {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            KeyRecorderView(chord: keyMap.map.chord(for: command)) { chord in
                record(chord, for: command)
            }
            MidiRecorderView(
                address: midiMap.map.address(for: command),
                onRecord: { address in recordMidi(address, for: command) },
                onClear: {
                    if let address = midiMap.map.address(for: command) {
                        midiMap.removeBinding(for: address)
                    }
                }
            )
        }
    }

    private func keywordRow(_ binding: KeywordBinding) -> some View {
        HStack {
            recorderRow(
                title: Text(binding.keyword).fontWeight(.medium),
                command: .keyword(binding.keyword)
            )
            // The trash clears BOTH bindings (spec §9.9).
            Button {
                if let chord = binding.chord {
                    keyMap.removeBinding(for: chord)
                }
                if let address = binding.address {
                    midiMap.removeBinding(for: address)
                }
                conflictHints[ActionCommand.keyword(binding.keyword).actionString] = nil
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
    }

    /// The add row offers the library's vocabulary as a menu (full paths, Q16
    /// order) instead of free text, so a binding can only target an existing
    /// node. Keywords that already have a row are left out.
    private var addKeywordRow: some View {
        HStack {
            Picker("Keyword", selection: $newKeywordName) {
                Text("Choose Keyword…").tag("")
                ForEach(unboundKeywordPaths, id: \.self) { path in
                    Text(path).tag(path)
                }
            }
            .labelsHidden()
            .frame(width: 220, alignment: .leading)
            Spacer()
            KeyRecorderView(chord: newKeywordChord) { newKeywordChord = $0 }
            MidiRecorderView(
                address: newKeywordAddress,
                onRecord: { newKeywordAddress = $0 },
                onClear: { newKeywordAddress = nil }
            )
            Button("Add") {
                addKeywordShortcut()
            }
            // A name plus at least one binding enables Add (spec §9.9).
            .disabled(
                newKeywordName.trimmingCharacters(in: .whitespaces).isEmpty
                    || (newKeywordChord == nil && newKeywordAddress == nil)
            )
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Reset Defaults") {
                // Restores the spec §12.3 key map and clears the MIDI map
                // entirely — there are no MIDI defaults (spec §9.9/§13.1).
                keyMap.resetToDefaults()
                midiMap.clearAll()
                conflictHints = [:]
            }
        }
        .padding(12)
    }

    // MARK: Model

    struct KeywordBinding {
        var keyword: String
        var chord: KeyChord?
        var address: MidiAddress?
    }

    /// One row per keyword that has a key OR MIDI binding (spec §9.9).
    private var keywordBindings: [KeywordBinding] {
        var keywords: Set<String> = []
        for value in keyMap.map.bindings.values {
            if case .keyword(let text)? = ActionCommand(actionString: value) {
                keywords.insert(text)
            }
        }
        for value in midiMap.map.bindings.values {
            if case .keyword(let text)? = ActionCommand(actionString: value) {
                keywords.insert(text)
            }
        }
        return keywords.sorted().map { keyword in
            KeywordBinding(
                keyword: keyword,
                chord: keyMap.map.chord(for: .keyword(keyword)),
                address: midiMap.map.address(for: .keyword(keyword))
            )
        }
    }

    private var unboundKeywordPaths: [String] {
        let bound = Set(keywordBindings.map(\.keyword))
        return (controller.snapshot?.keywordTree.allPaths() ?? []).filter { !bound.contains($0) }
    }

    private func record(_ chord: KeyChord, for command: ActionCommand) {
        // U11: name the binding this key is taken from instead of silently
        // stealing it. The 1:1 map semantics themselves stay per §12.4.
        if let previous = keyMap.map.command(for: chord), previous != command {
            conflictHints[command.actionString] = "was: \(displayName(of: previous))"
        } else {
            conflictHints[command.actionString] = nil
        }
        keyMap.assign(chord, to: command)
    }

    private func recordMidi(_ address: MidiAddress, for command: ActionCommand) {
        // Same overwrite hint as keys (U11), same 1:1 semantics (§13.1).
        if let previous = midiMap.map.command(for: address), previous != command {
            conflictHints[command.actionString] = "was: \(displayName(of: previous))"
        } else {
            conflictHints[command.actionString] = nil
        }
        midiMap.assign(address, to: command)
    }

    private func addKeywordShortcut() {
        let tree = controller.snapshot?.keywordTree ?? KeywordTree(records: [])
        guard let canonical = KeywordResolver.canonicalText(newKeywordName, tree: tree)
        else { return }
        if let chord = newKeywordChord {
            record(chord, for: .keyword(canonical))
        }
        if let address = newKeywordAddress {
            recordMidi(address, for: .keyword(canonical))
        }
        newKeywordName = ""
        newKeywordChord = nil
        newKeywordAddress = nil
    }

    private func displayName(of command: ActionCommand) -> String {
        switch command {
        case .app(let action): action.displayName
        case .keyword(let text): "Keyword \(text)"
        }
    }
}
