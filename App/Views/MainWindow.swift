import AppKit
import BallastCore
import SwiftUI

/// Three-pane layout per spec §9.1: sidebar 200–300, center min 400, inspector 250–350.
struct MainWindow: View {
    @Environment(LibraryController.self) private var controller
    @Environment(CenterViewModel.self) private var center
    @Environment(SidebarViewModel.self) private var sidebar
    @Environment(AppearanceStore.self) private var appearance
    /// The window's undo manager — handed to the controller so photo mutations
    /// are undoable via the standard Edit menu (U8) while text fields keep
    /// their own undo through the responder chain.
    @Environment(\.undoManager) private var windowUndoManager

    @FocusState private var searchFocused: Bool
    /// Closed on accept/submit even though text is still present (spec §11.3).
    @State private var showSearchSuggestions = false

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
        .onAppear {
            controller.undoManager = windowUndoManager
            // The search field must not grab first responder at launch —
            // focused text suppresses every culling shortcut (Q21). Clearing
            // initialFirstResponder also keeps later activations from
            // re-focusing it.
            DispatchQueue.main.async {
                for window in NSApp.windows where !(window is NSPanel) {
                    window.initialFirstResponder = nil
                    if window.firstResponder is NSText || window.firstResponder is NSTextView {
                        window.makeFirstResponder(nil)
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        }
        .overlay {
            if controller.isImporting || controller.isSyncing {
                ProgressView(controller.isImporting ? "Importing…" : "Syncing metadata…")
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
            "Library",
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
                SidebarView(sidebar: sidebar, center: center)
                    .frame(minWidth: 200, maxWidth: 300, maxHeight: .infinity)
            }
            centerPane
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            if center.showRightPanel {
                InspectorView()
                    .frame(minWidth: 250, maxWidth: 350, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var centerPane: some View {
        VStack(spacing: 0) {
            centerContent
                .overlay(alignment: .topTrailing) {
                    // U5: the active filter as a dismissible chip, floating
                    // above the content so it is visible in both modes even when the
                    // bottom bar is hidden or cramped (C6).
                    if !center.searchText.isEmpty {
                        searchChip
                            .padding(10)
                    }
                }
            if center.showBottomPanel {
                bottomBar
                    // The search dropdown overlays upward across the content.
                    .zIndex(1)
            }
        }
        .background(
            Color(hex: appearance.backgroundHex)
                ?? Color(hex: AppearanceStore.defaultBackgroundHex)!
        )
    }

    @ViewBuilder
    private var centerContent: some View {
        let photos = center.visiblePhotos
        if let pipeline = controller.thumbnails, !photos.isEmpty {
            Group {
                switch center.viewMode {
                case .grid:
                    PhotoGridView(
                        photos: photos, pipeline: pipeline, viewModel: center,
                        spacing: appearance.gridSpacing
                    )
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

    /// Bottom bar per spec §9.6 — mode switch and search in BOTH modes (C6/U5);
    /// slider + sort in grid mode; position indicator in single mode.
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

            searchField

            Spacer()

            switch center.viewMode {
            case .grid:
                Slider(
                    value: Binding(
                        get: { Double(center.columnCount) },
                        set: { center.columnCount = Int($0.rounded()) }
                    ),
                    in: 1...10,
                    step: 1
                )
                .frame(minWidth: 80, idealWidth: 150, maxWidth: 150)
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

    // MARK: Search (spec §11.3, C6/U5, Q21 via the focused-text-field pass-through)

    private var searchSuggestions: [String] {
        guard let tree = controller.snapshot?.keywordTree else { return [] }
        return KeywordAutocomplete.suggestions(for: center.searchText, tree: tree)
    }

    private var searchField: some View {
        @Bindable var center = center
        return TextField("Search", text: $center.searchText)
            .textFieldStyle(.roundedBorder)
            // 200 pt per spec §9.6, but compressible — at the 400 pt minimum
            // centre width the bar must never push the mode picker out.
            .frame(minWidth: 80, idealWidth: 200, maxWidth: 200)
            .focused($searchFocused)
            .onChange(of: center.searchText) {
                showSearchSuggestions = true
            }
            .onSubmit {
                showSearchSuggestions = false
            }
            .overlay(alignment: .topLeading) {
                let suggestions = searchSuggestions
                if searchFocused && showSearchSuggestions && !suggestions.isEmpty {
                    searchSuggestionList(suggestions)
                }
            }
    }

    /// Dropdown above the field (spec §11.3): clicking a suggestion replaces
    /// the search text with the full keyword path.
    private func searchSuggestionList(_ suggestions: [String]) -> some View {
        let height = min(CGFloat(suggestions.count) * 28, 150)
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(suggestions, id: \.self) { path in
                    Text(path)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            center.searchText = path
                            showSearchSuggestions = false
                        }
                }
            }
        }
        .frame(width: 200, height: height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
        .offset(y: -(height + 6))
    }

    /// U5: the active filter as a dismissible chip — visible in both modes, so
    /// a stale search can never invisibly truncate the list (C6).
    private var searchChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
            Text(center.searchText)
                .lineLimit(1)
                .truncationMode(.tail)
            Button {
                center.searchText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.25), in: Capsule())
    }
}
