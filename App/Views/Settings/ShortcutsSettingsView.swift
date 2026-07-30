import BallastCore
import SwiftUI

/// Settings ▸ Shortcuts (spec §9.9): one recorder row per app action, keyword
/// shortcut rows with an add row, Reset Defaults. Binding stays strictly 1:1
/// (§12.4) but overwrites are announced inline instead of silent (U11).
/// MIDI recorders join these rows in step 11.
struct ShortcutsSettingsView: View {
    @Environment(LibraryController.self) private var controller
    @Environment(KeyMapStore.self) private var keyMap

    /// U11: per-row "was: …" hint, keyed by the row's action string.
    @State private var conflictHints: [String: String] = [:]
    @State private var newKeywordName = ""
    @State private var newKeywordChord: KeyChord?

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
        }
    }

    private func keywordRow(_ binding: (keyword: String, chord: KeyChord?)) -> some View {
        HStack {
            recorderRow(
                title: Text(binding.keyword).fontWeight(.medium),
                command: .keyword(binding.keyword)
            )
            Button {
                if let chord = binding.chord {
                    keyMap.removeBinding(for: chord)
                }
                conflictHints["keyword:\(binding.keyword)"] = nil
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
    }

    /// New keyword shortcuts run through the same normalise-and-resolve pipeline
    /// as the panel (C7): binding `anna` stores `keyword:PEOPLE > ANNA` when the
    /// node exists, uppercased text otherwise.
    private var addKeywordRow: some View {
        HStack {
            TextField("Keyword", text: $newKeywordName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Spacer()
            KeyRecorderView(chord: newKeywordChord) { newKeywordChord = $0 }
            Button("Add") {
                addKeywordShortcut()
            }
            .disabled(
                newKeywordName.trimmingCharacters(in: .whitespaces).isEmpty
                    || newKeywordChord == nil
            )
        }
    }

    private var footer: some View {
        HStack {
            Text("Click 'None' or the existing key to record a new shortcut.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Reset Defaults") {
                // Restores the spec §12.3 map; keyword bindings are dropped
                // (and step 11 clears the MIDI map here too).
                keyMap.resetToDefaults()
                conflictHints = [:]
            }
        }
        .padding(12)
    }

    // MARK: Model

    private var keywordBindings: [(keyword: String, chord: KeyChord?)] {
        keyMap.map.bindings
            .compactMap { key, value -> (keyword: String, chord: KeyChord?)? in
                guard case .keyword(let text)? = ActionCommand(actionString: value) else {
                    return nil
                }
                return (text, KeyChord(keyString: key))
            }
            .sorted { $0.keyword < $1.keyword }
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

    private func addKeywordShortcut() {
        let tree = controller.snapshot?.keywordTree ?? KeywordTree(records: [])
        guard let chord = newKeywordChord,
              let canonical = KeywordResolver.canonicalText(newKeywordName, tree: tree)
        else { return }
        record(chord, for: .keyword(canonical))
        newKeywordName = ""
        newKeywordChord = nil
    }

    private func displayName(of command: ActionCommand) -> String {
        switch command {
        case .app(let action): action.displayName
        case .keyword(let text): "Keyword \(text)"
        }
    }
}
