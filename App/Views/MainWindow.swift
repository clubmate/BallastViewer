import SwiftUI
import BallastCore

/// Three-pane layout per spec §9.1: sidebar 200–300, center min 400, inspector 250–350.
/// Panels are placeholders until their steps land (sidebar: step 7, grid: step 5, inspector: step 8).
struct MainWindow: View {
    @Environment(LibraryController.self) private var controller
    @Environment(CenterViewModel.self) private var center

    var body: some View {
        Group {
            if controller.isLibraryOpen {
                libraryContent
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .navigationTitle(controller.libraryURL?.lastPathComponent ?? "ballastviewer")
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
            if center.showLeftPanel {
                sidebarPlaceholder
                    .frame(minWidth: 200, maxWidth: 300, maxHeight: .infinity)
            }
            centerPane
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            if center.showRightPanel {
                inspectorPlaceholder
                    .frame(minWidth: 250, maxWidth: 350, maxHeight: .infinity)
            }
        }
    }

    private var sidebarPlaceholder: some View {
        Text("LIBRARY")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
    }

    @ViewBuilder
    private var centerPane: some View {
        VStack(spacing: 0) {
            centerContent
            if center.showBottomPanel {
                bottomBar
            }
        }
        // Default background until the Settings appearance tab lands (spec §9.5).
        .background(Color(red: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x1E / 255.0))
    }

    @ViewBuilder
    private var centerContent: some View {
        let photos = center.visiblePhotos
        if let pipeline = controller.thumbnails, !photos.isEmpty {
            Group {
                switch center.viewMode {
                case .grid:
                    PhotoGridView(photos: photos, pipeline: pipeline, viewModel: center)
                case .single:
                    SingleView(photo: center.anchorPhoto, pipeline: pipeline)
                }
            }
            .task(id: photos.count) {
                await PerfProbe.runIfRequested(
                    photos: photos, viewModel: center, pipeline: pipeline
                )
            }
        } else if controller.snapshot?.photos.isEmpty ?? true {
            emptyState(
                title: "No Photos",
                message: "Add a folder to import photos."
            )
        } else {
            // Photos exist but the active filter matches none (spec §9.5).
            emptyState(
                title: "No Photos Found",
                message: "No photos match the current selection."
            )
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Bottom bar per spec §9.6 — mode switch always; slider + sort in grid
    /// mode; position indicator in single mode. Search arrives in step 9.
    private var bottomBar: some View {
        @Bindable var center = center
        return HStack {
            Picker("View Mode", selection: $center.viewMode) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                Image(systemName: "rectangle").tag(ViewMode.single)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            switch center.viewMode {
            case .grid:
                // Interim stand-in for the sidebar's unrated pseudo-collection;
                // replaced by real collections in step 7.
                Toggle("Unrated", isOn: $center.unratedOnly)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                Slider(
                    value: Binding(
                        get: { Double(center.columnCount) },
                        set: { center.columnCount = Int($0.rounded()) }
                    ),
                    in: 1...10,
                    step: 1
                )
                .frame(width: 150)
                Picker("Sort", selection: $center.sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .fixedSize()
            case .single:
                Text("\(center.anchorPosition.map { String($0 + 1) } ?? "–") / \(center.visiblePhotos.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
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
