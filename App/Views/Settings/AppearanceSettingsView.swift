import SwiftUI

/// Settings ▸ Appearance: centre background and selection colours. Grid
/// spacing is fixed in code (`PhotoGridView.spacing`). Values live in
/// `AppearanceStore` (UserDefaults).
struct AppearanceSettingsView: View {
    @Environment(AppearanceStore.self) private var appearance

    var body: some View {
        Form {
            Section("Color") {
                ColorPicker(
                    "Background Color",
                    selection: colorBinding(\.backgroundHex),
                    supportsOpacity: true
                )
                ColorPicker(
                    "Selection Color",
                    selection: colorBinding(\.selectionHex),
                    supportsOpacity: false
                )
            }
        }
        .formStyle(.grouped)
    }

    /// Round-trips through the canonical `#RRGGBBAA` codec (C8).
    private func colorBinding(
        _ keyPath: ReferenceWritableKeyPath<AppearanceStore, String>
    ) -> Binding<Color> {
        Binding(
            get: { Color(hex: appearance[keyPath: keyPath]) ?? .clear },
            set: { newColor in
                if let hex = newColor.canonicalHex {
                    appearance[keyPath: keyPath] = hex
                }
            }
        )
    }
}

/// Settings ▸ MIDI: debounce and LED output device (spec §9.9, U12).
struct MidiSettingsView: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(MidiService.self) private var midi

    var body: some View {
        @Bindable var appearance = appearance
        Form {
            Section("MIDI") {
                TextField(
                    "Debounce Time (ms)",
                    value: $appearance.midiDebounceMs,
                    format: .number
                )
                Text("Prevents double-triggering")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("LED Output Device", selection: $appearance.midiOutputDestination) {
                    Text("All Destinations").tag("")
                    ForEach(midi.destinationNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
