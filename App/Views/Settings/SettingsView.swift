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
            KeywordsSettingsView()
                .tabItem { Label("Keywords", systemImage: "tag") }
                .tag(SettingsRouter.Tab.keywords)
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsRouter.Tab.shortcuts)
        }
        .frame(width: 600, height: 500)
    }
}
