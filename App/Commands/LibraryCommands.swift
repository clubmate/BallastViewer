import SwiftUI

/// The Library menu (spec §14.1). Add Folder / metadata sync items arrive with
/// their steps. Library shown by filename with extension consistently (U13).
struct LibraryCommands: Commands {
    let controller: LibraryController

    var body: some Commands {
        CommandMenu("Library") {
            if let url = controller.libraryURL {
                Text("Current: \(url.lastPathComponent)")
                Divider()
            }

            Button("New Library…") { controller.presentNewLibraryPanel() }
                .keyboardShortcut("n", modifiers: [.shift, .command])
            Button("Open Library…") { controller.presentOpenLibraryPanel() }
                .keyboardShortcut("o", modifiers: [.shift, .command])

            Menu("Open Recent") {
                ForEach(controller.recentLibraries, id: \.path) { url in
                    Button(url.lastPathComponent) { controller.openLibrary(at: url) }
                }
                if !controller.recentLibraries.isEmpty {
                    Divider()
                    Button("Clear Menu") { controller.clearRecents() }
                }
            }

            if controller.isLibraryOpen {
                Divider()
                Button("Add Folder…") { controller.presentAddFolderPanel() }
                    .keyboardShortcut("i", modifiers: [.shift, .command])
                if let folders = controller.snapshot?.folders, !folders.isEmpty {
                    Menu("Remove Folder") {
                        ForEach(folders, id: \.path) { folder in
                            Button(folder.path) { controller.requestRemoveFolder(folder) }
                        }
                    }
                }
                Divider()
                // Distinct wording for the two sync directions (U12) — the
                // original used one alert text for both.
                Button("Save Metadata into Files") {
                    Task { await controller.saveMetadataToFiles() }
                }
                .disabled(controller.isSyncing)
                Button("Load Metadata from Files") {
                    Task { await controller.loadMetadataFromFiles() }
                }
                .disabled(controller.isSyncing)
                Divider()
                Button("Close Library") { controller.closeLibrary() }
            }
        }
    }
}
