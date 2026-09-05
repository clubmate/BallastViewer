import SwiftUI

/// Fixed 600×500 settings window; the spec §9.9 tabs plus Libraries (U14 —
/// library and folder management moved here from the menu).
struct SettingsView: View {
    @Environment(SettingsRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            LibrariesSettingsView()
                .tabItem { Label("Libraries", systemImage: "books.vertical") }
                .tag(SettingsRouter.Tab.libraries)
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsRouter.Tab.appearance)
            MidiSettingsView()
                .tabItem { Label("MIDI", systemImage: "pianokeys") }
                .tag(SettingsRouter.Tab.midi)
            KeywordsSettingsView()
                .tabItem { Label("Keywords", systemImage: "tag") }
                .tag(SettingsRouter.Tab.keywords)
            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(SettingsRouter.Tab.ai)
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsRouter.Tab.shortcuts)
            BackupSettingsView()
                .tabItem { Label("Backup", systemImage: "externaldrive.badge.timemachine") }
                .tag(SettingsRouter.Tab.backup)
        }
        .frame(width: 600, height: 500)
    }
}
