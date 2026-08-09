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
    @Environment(\.displayScale) private var displayScale

    @FocusState private var searchFocused: Bool
    /// Closed on accept/submit even though text is still present (spec §11.3).
    @State private var showSearchSuggestions = false
    /// Set when the search text changes programmatically (accepted suggestion)
    /// so the text-change observer keeps the dropdown closed.
    @State private var suppressNextSuggestionOpen = false
    /// Panel widths, owned by us (not a split view — see libraryContent) so
    /// hide/show round-trips and relaunches keep the exact width. Persisted
    /// on drag end.
    @State private var sidebarWidth: CGFloat = Self.storedPanelWidth(
        "sidebarPanelWidth", fallback: 300
    )
    @State private var inspectorWidth: CGFloat = Self.storedPanelWidth(
        "inspectorPanelWidth", fallback: 350
    )
    /// Width of the pane being dragged, captured at drag start.
    @State private var paneDragBase: CGFloat?

    private static func storedPanelWidth(_ key: String, fallback: CGFloat) -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: key)
        return stored > 0 ? stored : fallback
    }

    /// Titlebar-separator tone: soft black over the dark chrome, fainter in
    /// light mode.
    private static let titlebarSeparatorColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.black.withAlphaComponent(0.5)
            : NSColor.black.withAlphaComponent(0.15)
    })

    var body: some View {
        VStack(spacing: 0) {
            // Always-on titlebar separator in AppKit's own tone (black in dark
            // mode, soft black in light) — the system separator is unreliable
            // with a transparent titlebar (.automatic flickers with layout
            // state, .line draws nothing at all), so this line is ours.
            Rectangle()
                .fill(Self.titlebarSeparatorColor)
                // One DEVICE pixel — a 1 pt line is two pixels on Retina and
                // reads as too thick.
                .frame(height: 1 / displayScale)
            if controller.isLibraryOpen {
                libraryContent
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        // THE chrome surface: one .bar material for the whole window backdrop,
        // extending under the transparent titlebar (backgrounds ignore the
        // safe area). Panels, bars and dividers stay transparent and show this
        // through — a second material layer on top would shift the tone, and
        // the AppKit titlebar would otherwise tint differently over the dark
        // grid than over the panels.
        .background(.bar)
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

    /// Hand-rolled three-pane layout. HSplitView was dropped deliberately: its
    /// divider renders an unstylable black line, and it re-adds a hidden pane
    /// at its ideal width (ignoring `idealWidth`), so every panel toggle
    /// resized the grid. Here the widths are plain state.
    private var libraryContent: some View {
        HStack(spacing: 0) {
            if center.showLeftPanel {
                SidebarView(sidebar: sidebar, center: center)
                    .frame(width: sidebarWidth)
                paneDivider { delta in
                    if paneDragBase == nil { paneDragBase = sidebarWidth }
                    sidebarWidth = min(300, max(200, paneDragBase! + delta))
                } commit: {
                    UserDefaults.standard.set(Double(sidebarWidth), forKey: "sidebarPanelWidth")
                }
            }
            centerPane
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            if center.showRightPanel {
                paneDivider { delta in
                    if paneDragBase == nil { paneDragBase = inspectorWidth }
                    inspectorWidth = min(350, max(250, paneDragBase! - delta))
                } commit: {
                    UserDefaults.standard.set(Double(inspectorWidth), forKey: "inspectorPanelWidth")
                }
                InspectorView()
                    .frame(width: inspectorWidth)
            }
        }
    }

    /// A 1 pt divider in the panel material with a wider invisible grab area.
    /// `resize` receives the cumulative drag delta; `commit` runs on drag end.
    private func paneDivider(
        resize: @escaping (CGFloat) -> Void, commit: @escaping () -> Void
    ) -> some View {
        Color.clear
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { resize($0.translation.width) }
                            .onEnded { _ in
                                paneDragBase = nil
                                commit()
                            }
                    )
            }
    }

    @ViewBuilder
    private var centerPane: some View {
        VStack(spacing: 0) {
            centerContent
                // The appearance color backs the CONTENT only — not the bar
                // below, and not the titlebar above (ignoresSafeAreaEdges: []);
                // both belong to the window-wide .bar material.
                .background(
                    Color(hex: appearance.backgroundHex)
                        ?? Color(hex: AppearanceStore.defaultBackgroundHex)!,
                    ignoresSafeAreaEdges: []
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
                    SingleView(
                        photo: center.anchorPhoto,
                        neighbors: center.anchorNeighbors,
                        pipeline: pipeline
                    )
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
        VStack(spacing: 0) {
            Divider()
            bottomBarContent
        }
    }

    private var bottomBarContent: some View {
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

                // No step: — a stepped macOS slider draws tick marks; the
                // binding rounds to whole columns anyway.
                Slider(
                    value: Binding(
                        get: { Double(center.columnCount) },
                        set: { center.columnCount = Int($0.rounded()) }
                    ),
                    in: 1...10
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
        .frame(height: PanelMetrics.footerHeight)
    }

    // MARK: Search (spec §11.3, C6/U5, Q21 via the focused-text-field pass-through)


    private var searchSuggestions: [String] {
        guard let tree = controller.snapshot?.keywordTree else { return [] }
        return KeywordAutocomplete.suggestions(for: center.searchText, tree: tree)
    }

    /// Same visual recipe as the inspector's Add Keyword field: a plain text
    /// field in a controlBackgroundColor rounded rect — a bordered field is
    /// invisible against the bar material.
    private var searchField: some View {
        @Bindable var center = center
        return HStack(spacing: 4) {
            TextField("Search", text: $center.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onChange(of: center.searchText) {
                    // A programmatic change (accepted suggestion) must not
                    // reopen the dropdown — "closed on accept" (spec §11.3).
                    if suppressNextSuggestionOpen {
                        suppressNextSuggestionOpen = false
                    } else {
                        showSearchSuggestions = true
                    }
                }
                .onSubmit {
                    showSearchSuggestions = false
                }
            if !center.searchText.isEmpty {
                Button {
                    center.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 1)
        )
        // 200 pt per spec §9.6, but compressible — at the 400 pt minimum
        // centre width the bar must never push the mode picker out.
        .frame(minWidth: 80, idealWidth: 200, maxWidth: 200)
        .overlay(alignment: .topLeading) {
                // Visibility first — the suggestion computation walks every
                // keyword path and must not run on unrelated body passes.
                if searchFocused && showSearchSuggestions {
                    let suggestions = searchSuggestions
                    if !suggestions.isEmpty {
                        searchSuggestionList(suggestions)
                    }
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
                            suppressNextSuggestionOpen = true
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
                view?.window.map(Self.configureTitlebar)
            }
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            if let window = view.window, ShortcutMonitor.mainWindow !== window {
                DispatchQueue.main.async {
                    ShortcutMonitor.mainWindow = window
                    Self.configureTitlebar(window)
                }
            }
        }

        /// The AppKit titlebar blends with the content region below it, so its
        /// tone shifted whenever the layout under it changed (panel toggles).
        /// Transparent titlebar + full-size content lets the root .bar
        /// material own that area instead — one deterministic surface.
        private static func configureTitlebar(_ window: NSWindow) {
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            // The system separator cannot be used with a transparent titlebar
            // (.automatic flickers, .line draws nothing) — we draw our own.
            window.titlebarSeparatorStyle = .none
        }
    }
}
