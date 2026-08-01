import AppKit
import BallastCore
import SwiftUI

/// Three-pane layout per spec §9.1: sidebar 200–300, center min 400, inspector 250–350.
/// Shared metrics + surface convention for the three chrome panels (sidebar,
/// inspector, bottom bar): all use the `.bar` material composited on the bare
/// window backdrop, and their bottom rows share one height so the sidebar and
/// inspector footers align with the bottom bar. Plain window/control background
/// colors are #1E1E1E in dark mode — identical to the default grid background
/// and therefore useless for separating chrome from content.
enum PanelMetrics {
    static let barHeight: CGFloat = 42
    /// Footer row height inside panels that put a 1 pt Divider above it.
    static let footerHeight: CGFloat = barHeight - 1
}

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
        .background(MainWindowRegistrar())
        .onAppear {
            controller.undoManager = windowUndoManager
            // Bound so a pathological undo entry (a 50k-photo folder removal
            // captures every row) cannot accumulate without limit.
            windowUndoManager?.levelsOfUndo = 50
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
                get: { controller.errorMessage != nil && !TestHooks.suppressesAlerts },
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
                get: { controller.infoMessage != nil && !TestHooks.suppressesAlerts },
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
                // The appearance color backs the CONTENT only — the bar below
                // must composite its material on the plain window backdrop,
                // exactly like the side panels, or the tones diverge.
                .background(
                    Color(hex: appearance.backgroundHex)
                        ?? Color(hex: AppearanceStore.defaultBackgroundHex)!
                )
            if center.showBottomPanel {
                bottomBar
                    // The search dropdown overlays upward across the content.
                    .zIndex(1)
            }
        }
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
                    photos: photos, viewModel: center, pipeline: pipeline,
                    controller: controller
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

    /// Bottom bar per spec §9.6 — mode switch in both modes; search, slider and
    /// sort in grid mode only. The search filter stays active across the mode
    /// change, so single mode names it (with the position among the matches) —
    /// otherwise the filter would invisibly truncate the list (C6).
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

            if center.viewMode == .grid {
                searchField

                Spacer()

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
            } else {
                Spacer()
                if !center.searchText.isEmpty {
                    Text(
                        "Active search: \(center.searchText) "
                            + "(\(center.anchorPosition.map { String($0 + 1) } ?? "–")/\(center.visiblePhotos.count))"
                    )
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: PanelMetrics.barHeight)
        // Same surface as the side panels (see PanelMetrics).
        .background(.bar)
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
            .overlay(alignment: .trailing) {
                if !center.searchText.isEmpty {
                    Button {
                        center.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
                }
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

    /// Hands the hosting NSWindow to the ShortcutMonitor whitelist.
    private struct MainWindowRegistrar: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { [weak view] in
                ShortcutMonitor.mainWindow = view?.window
            }
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            if let window = view.window, ShortcutMonitor.mainWindow !== window {
                DispatchQueue.main.async {
                    ShortcutMonitor.mainWindow = window
                }
            }
        }
    }
}
