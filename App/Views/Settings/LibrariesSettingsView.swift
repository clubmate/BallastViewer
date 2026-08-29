import BallastCore
import SwiftUI

/// Settings ▸ Libraries (U14): pure MANAGEMENT — the select field picks which
/// library to manage (it never opens anything; switching happens in the
/// Library menu). Below it: that library's folders with add/remove, plus
/// create / add-existing / delete.
struct LibrariesSettingsView: View {
    @Environment(LibraryController.self) private var controller

    @State private var selectedPath = ""
    @State private var managedFolders: [FolderRecord] = []
    /// The name field's text plus the library it belongs to — captured at load
    /// so a commit racing a selection switch never renames the wrong library.
    @State private var editedName = ""
    @State private var editedNamePath = ""
    @FocusState private var nameFieldFocused: Bool
    /// Pending "delete library" confirmation — the package goes to the Trash.
    @State private var pendingDelete: URL?
    /// Pending folder-removal confirmation (U7, with photo count).
    @State private var pendingFolderRemoval: FolderRemoval?

    struct FolderRemoval: Identifiable {
        let folder: FolderRecord
        let photoCount: Int
        var id: String { folder.path }
    }

    private var sortedLibraries: [URL] {
        controller.knownLibraries.sorted {
            controller.displayName(for: $0)
                .localizedCaseInsensitiveCompare(controller.displayName(for: $1))
                == .orderedAscending
        }
    }

    private var selectedURL: URL? {
        controller.knownLibraries.first { $0.path == selectedPath }
    }

    /// What to manage when nothing valid is selected: the open library,
    /// else the first by name, else nothing.
    private var defaultSelectionPath: String {
        controller.libraryURL?.path ?? sortedLibraries.first?.path ?? ""
    }

    var body: some View {
        Form {
            librarySection
            foldersSection
        }
        .formStyle(.grouped)
        // Closing/switching/deleting the open library and removing its folders
        // are refused while a bulk transaction runs (LibraryController.isBusy).
        .disabled(controller.isBusy)
        .onAppear {
            if selectedURL == nil { selectedPath = defaultSelectionPath }
            reloadFolders()
            loadEditedName()
        }
        .onChange(of: selectedPath) {
            // A rename typed just before switching still belongs to the
            // previous selection — commit it before the field is reloaded.
            commitName()
            reloadFolders()
            loadEditedName()
        }
        .onChange(of: controller.knownLibraries.map(\.path)) {
            if selectedURL == nil { selectedPath = defaultSelectionPath }
            reloadFolders()
            loadEditedName()
        }
        // Imports finish asynchronously — refresh the folder list afterwards.
        .onChange(of: controller.isImporting) { _, importing in
            if !importing { reloadFolders() }
        }
        .alert(
            "Delete Library",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { url in
            Button("Move to Trash", role: .destructive) {
                controller.deleteLibrary(at: url)
            }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text("Move “\(controller.displayName(for: url))” to the Trash?\nYour photo files on disk are not touched — only the library catalog is deleted.")
        }
        .alert(
            "Remove Folder",
            isPresented: Binding(
                get: { pendingFolderRemoval != nil },
                set: { if !$0 { pendingFolderRemoval = nil } }
            ),
            presenting: pendingFolderRemoval
        ) { removal in
            Button(
                "Remove \(removal.photoCount) Photo\(removal.photoCount == 1 ? "" : "s")",
                role: .destructive
            ) {
                guard let url = selectedURL else { return }
                Task {
                    await controller.removeFolder(removal.folder, fromLibraryAt: url)
                    reloadFolders()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { removal in
            Text("Remove “\(removal.folder.path)” and its \(removal.photoCount) photo\(removal.photoCount == 1 ? "" : "s") from this library?\nYour files on disk are not touched.")
        }
    }

    // MARK: Libraries

    private var librarySection: some View {
        Section("Libraries") {
            if controller.knownLibraries.isEmpty {
                Text("No libraries yet.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Library", selection: $selectedPath) {
                    ForEach(sortedLibraries, id: \.path) { url in
                        Text(controller.displayName(for: url)).tag(url.path)
                    }
                }
                TextField(
                    "Name",
                    text: $editedName,
                    prompt: Text(selectedURL?.lastPathComponent ?? "")
                )
                .focused($nameFieldFocused)
                .onSubmit { commitName() }
                .onChange(of: nameFieldFocused) { _, focused in
                    if !focused { commitName() }
                }
            }
            HStack {
                Button("New Library…") { controller.presentNewLibraryPanel() }
                Button("Add Existing…") { controller.presentAddExistingLibraryPanel() }
                Spacer()
                Button("Delete Library…") {
                    pendingDelete = selectedURL
                }
                .foregroundStyle(.red)
                .disabled(selectedURL == nil)
            }
        }
    }

    // MARK: Folders of the selected library

    @ViewBuilder
    private var foldersSection: some View {
        if let url = selectedURL {
            Section("Folders in \(controller.displayName(for: url))") {
                if managedFolders.isEmpty {
                    Text("No folders imported yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(managedFolders, id: \.path) { folder in
                    HStack {
                        Text(folder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            Task {
                                pendingFolderRemoval = FolderRemoval(
                                    folder: folder,
                                    photoCount: await controller.folderPhotoCount(folder, inLibraryAt: url)
                                )
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                Button("Add Folder…") { controller.presentAddFolderPanel(for: url) }
            }
        }
    }

    /// Loads the stored name of the current selection into the field.
    private func loadEditedName() {
        editedName = selectedURL.flatMap { controller.libraryNames[$0.path] } ?? ""
        editedNamePath = selectedPath
    }

    /// Persists the field if it actually changed. Keyed to `editedNamePath`,
    /// not the live selection — see the state declaration.
    private func commitName() {
        guard let url = controller.knownLibraries.first(where: { $0.path == editedNamePath })
        else { return }
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (controller.libraryNames[url.path] ?? "") else { return }
        Task { await controller.setLibraryName(trimmed, forLibraryAt: url) }
    }

    private func reloadFolders() {
        guard let url = selectedURL else {
            managedFolders = []
            return
        }
        Task {
            let folders = await controller.folders(inLibraryAt: url)
            // The selection may have moved on while the closed library loaded.
            if url.path == selectedPath {
                managedFolders = folders
            }
        }
    }
}
