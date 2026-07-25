import SwiftUI
import BallastCore

/// Three-pane layout per spec §9.1: sidebar 200–300, center min 400, inspector 250–350.
/// Panels are placeholders until their steps land (sidebar: step 7, grid: step 5, inspector: step 8).
struct MainWindow: View {
    @Environment(LibraryController.self) private var controller
    @State private var gridViewModel = GridViewModel()

    var body: some View {
        @Bindable var controller = controller
        Group {
            if controller.isLibraryOpen {
                libraryContent
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .navigationTitle(controller.libraryURL?.lastPathComponent ?? "ballastviewer")
        .onChange(of: controller.libraryURL) {
            gridViewModel.selection = SelectionModel()
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        }
        .overlay {
            if controller.isImporting {
                ProgressView("Importing…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert(
            "ballastviewer",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.errorMessage ?? "")
        }
        .alert(
            "Import",
            isPresented: Binding(
                get: { controller.infoMessage != nil },
                set: { if !$0 { controller.infoMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.infoMessage ?? "")
        }
        .alert(
            "Remove Folder",
            isPresented: Binding(
                get: { controller.pendingFolderRemoval != nil },
                set: { if !$0 { controller.pendingFolderRemoval = nil } }
            ),
            presenting: controller.pendingFolderRemoval
        ) { pending in
            Button("Remove \(pending.photoCount) Photo\(pending.photoCount == 1 ? "" : "s")", role: .destructive) {
                controller.confirmRemoveFolder(pending)
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text("Remove “\(pending.folder.path)” and its \(pending.photoCount) photo\(pending.photoCount == 1 ? "" : "s") from the catalog?\nYour files on disk are not touched.")
        }
    }

    /// Folder drop imports into the open library, or offers to create one first (U1/U2).
    private func handleDrop(_ urls: [URL]) -> Bool {
        let folders = urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        guard !folders.isEmpty else { return false }
        if controller.isLibraryOpen {
            Task { await controller.importFolders(folders, recursive: true) }
        } else {
            controller.handleDropWithoutLibrary(folders)
        }
        return true
    }

    private var libraryContent: some View {
        HSplitView {
            sidebarPlaceholder
                .frame(minWidth: 200, maxWidth: 300, maxHeight: .infinity)
            centerPlaceholder
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            inspectorPlaceholder
                .frame(minWidth: 250, maxWidth: 350, maxHeight: .infinity)
        }
    }

    private var sidebarPlaceholder: some View {
        Text("LIBRARY")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
    }

    private var gridPhotos: [GridPhoto] {
        controller.snapshot?.photos.compactMap { photo in
            photo.id.map { GridPhoto(id: $0, path: photo.path, orientation: photo.orientation) }
        } ?? []
    }

    @ViewBuilder
    private var centerPlaceholder: some View {
        let photos = gridPhotos
        if !photos.isEmpty, let pipeline = controller.thumbnails {
            VStack(spacing: 0) {
                PhotoGridView(photos: photos, pipeline: pipeline, viewModel: gridViewModel)
                bottomBar(photoCount: photos.count)
            }
            // Default background until the Settings appearance tab lands.
            .background(Color(red: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x1E / 255.0))
            .task(id: photos.count) {
                await PerfProbe.runIfRequested(
                    photos: photos, viewModel: gridViewModel, pipeline: pipeline
                )
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No Photos")
                    .font(.title)
                Text("Add a folder to import photos.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Minimal bottom bar — grows into the full spec §9.6 bar in step 6.
    private func bottomBar(photoCount: Int) -> some View {
        @Bindable var gridViewModel = gridViewModel
        return HStack {
            Text("\(photoCount) photos")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Slider(
                value: Binding(
                    get: { Double(gridViewModel.columnCount) },
                    set: { gridViewModel.columnCount = Int($0.rounded()) }
                ),
                in: 1...10,
                step: 1
            )
            .frame(width: 150)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var inspectorPlaceholder: some View {
        Text("No Selection")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(8)
    }
}
