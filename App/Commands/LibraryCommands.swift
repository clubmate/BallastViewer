import SwiftUI

/// The Library menu, U14: a plain switcher — one entry per known library with
/// a checkmark on the open one, plus a jump into Settings ▸ Libraries. All
/// management (create, open, folders) lives in Settings; day-to-day import
/// still works via folder drag & drop and the sidebar button. BallastPicker
/// (U16) sits here too: it is the tool used before a folder joins a library.
struct LibraryCommands: Commands {
    let controller: LibraryController
    let settingsRouter: SettingsRouter

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Library") {
            if controller.knownLibraries.isEmpty {
                Text("No Libraries")
            }
            ForEach(controller.knownLibraries, id: \.path) { url in
                Toggle(
                    controller.displayName(for: url),
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
            Divider()
            // Merges ratings + keywords from an .lrcat into photos already in
            // the open library — imports metadata, never images.
            Button("Import Metadata from Lightroom…") {
                controller.presentImportLightroomPanel()
            }
            .disabled(controller.libraryURL == nil || controller.isBusy)
            Divider()
            Button("BallastPicker") { openWindow(id: "photoPicker") }
                .keyboardShortcut("p", modifiers: [.shift, .command])
        }
    }
}
