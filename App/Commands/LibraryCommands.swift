import SwiftUI

/// The Library menu, U14: a plain switcher — one entry per known library with
/// a checkmark on the open one, plus a jump into Settings ▸ Libraries. All
/// management (create, open, folders) lives in Settings; day-to-day import
/// still works via folder drag & drop and the sidebar button.
struct LibraryCommands: Commands {
    let controller: LibraryController
    let settingsRouter: SettingsRouter

    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandMenu("Library") {
            if controller.knownLibraries.isEmpty {
                Text("No Libraries")
            }
            ForEach(controller.knownLibraries, id: \.path) { url in
                Toggle(
                    url.lastPathComponent,
                    isOn: Binding(
                        get: { url.path == controller.libraryURL?.path },
                        set: { selected in
                            if selected { Task { await controller.openLibrary(at: url) } }
                        }
                    )
                )
            }
            Divider()
            Button("Manage Libraries…") {
                settingsRouter.selectedTab = .libraries
                openSettings()
            }
            .keyboardShortcut("l", modifiers: [.shift, .command])
        }
    }
}
