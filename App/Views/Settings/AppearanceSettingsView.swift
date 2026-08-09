import SwiftUI

/// Settings ▸ Appearance (spec §9.9): grid spacing, centre background color,
/// MIDI debounce. All values live in `AppearanceStore` (UserDefaults).
struct AppearanceSettingsView: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(MidiService.self) private var midi

    var body: some View {
        @Bindable var appearance = appearance
        Form {
            Section("Grid") {
                HStack {
                    Slider(value: $appearance.gridSpacing, in: 0...50, step: 1) {
                        Text("Spacing between images")
                    }
                    Text("\(Int(appearance.gridSpacing)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Section("Background") {
                ColorPicker(
                    "Background Color",
                    selection: backgroundBinding,
                    supportsOpacity: true
                )
            }
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

    /// Round-trips through the canonical `#RRGGBBAA` codec (C8).
    private var backgroundBinding: Binding<Color> {
        Binding(
            get: {
                Color(hex: appearance.backgroundHex)
                    ?? Color(hex: AppearanceStore.defaultBackgroundHex)!
            },
            set: { newColor in
                if let hex = newColor.canonicalHex {
                    appearance.backgroundHex = hex
                }
            }
        )
    }
}
