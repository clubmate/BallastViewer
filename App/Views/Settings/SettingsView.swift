import SwiftUI

/// Fixed 600×500 settings window, three tabs (spec §9.9).
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            KeywordsSettingsView()
                .tabItem { Label("Keywords", systemImage: "tag") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 600, height: 500)
    }
}
