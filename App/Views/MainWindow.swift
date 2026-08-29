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

    /// Panel widths, owned by us (not a split view — see libraryContent) so
    /// hide/show round-trips and relaunches keep the exact width. Persisted
    /// on drag end.
    @State private var sidebarWidth: CGFloat = Self.storedPanelWidth(
        "sidebarPanelWidth", range: Self.sidebarWidthRange, fallback: 300
    )
    @State private var inspectorWidth: CGFloat = Self.storedPanelWidth(
        "inspectorPanelWidth", range: Self.inspectorWidthRange, fallback: 350
    )
    /// The PaneDivider ranges (spec §9.1) — persisted widths are clamped to
    /// them so a stale or hand-edited default cannot open a pane at a width
    /// the divider could never produce.
    private static let sidebarWidthRange: ClosedRange<CGFloat> = 200...300
    private static let inspectorWidthRange: ClosedRange<CGFloat> = 250...350

    private static func storedPanelWidth(
        _ key: String, range: ClosedRange<CGFloat>, fallback: CGFloat
    ) -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: key)
        guard stored > 0 else { return fallback }
        return min(range.upperBound, max(range.lowerBound, CGFloat(stored)))
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
        .navigationTitle(controller.libraryURL.map { controller.displayName(for: $0) } ?? "BallastViewer")
        .background(MainWindowRegistrar())
        // The environment undo manager can be nil on the first body pass and
        // arrive later; onAppear alone would then leave Edit ▸ Undo dead.
        .onChange(of: windowUndoManager, initial: true) {
            controller.undoManager = windowUndoManager
            // Bound so a pathological undo entry (a 50k-photo folder removal
            // captures every row) cannot accumulate without limit.
            windowUndoManager?.levelsOfUndo = 50
        }
        .onAppear {
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
        // A real modal shield: while a bulk transaction runs, clicks and
        // keyboard/MIDI actions (guarded in ShortcutMonitor/ActionDispatcher)
        // must not queue mutations behind it, or memory and DB diverge.
        .allowsHitTesting(!controller.isBusy)
        .overlay {
            if controller.isBusy {
                ProgressView(controller.isImporting ? "Importing…" : "Working…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert(
            "BallastViewer",
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
                PaneDivider(width: $sidebarWidth, range: Self.sidebarWidthRange, direction: 1) {
                    UserDefaults.standard.set(Double(sidebarWidth), forKey: "sidebarPanelWidth")
                }
            }
            centerPane
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            if center.showRightPanel {
                PaneDivider(width: $inspectorWidth, range: Self.inspectorWidthRange, direction: -1) {
                    UserDefaults.standard.set(Double(inspectorWidth), forKey: "inspectorPanelWidth")
                }
                InspectorView()
                    .frame(width: inspectorWidth)
            }
        }
    }

    @ViewBuilder
    private var centerPane: some View {
        VStack(spacing: 0) {
            centerContent
                // The appearance color backs the CONTENT only — not the bar
                // below, and not the titlebar above (ignoresSafeAreaEdges: []);
                // both belong to the window-wide .bar material.
                .background(appearance.backgroundColor, ignoresSafeAreaEdges: [])
            if center.showBottomPanel {
                BottomBar(center: center, controller: controller)
                    // The search dropdown overlays upward across the content.
                    .zIndex(1)
            }
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        let photos = center.visiblePhotos
        if let pipeline = controller.thumbnails {
            let isGrid = center.viewMode == .grid
            // The grid lives for as long as the pipeline does and is only
            // HIDDEN — in single mode and while the visible list is empty.
            // Swapping it out rebuilt the NSCollectionView (new coordinator,
            // full reloadData, O(n) layout) on every grid⇄single toggle and
            // on every filter that briefly matched nothing, and lost the
            // scroll position. The single view is cheap to recreate and
            // would otherwise keep decoding originals for every anchor move
            // while hidden, so it IS swapped. The empty-state text is an
            // overlay on top of the (empty) grid.
            ZStack {
                PhotoGridView(
                    photos: photos, pipeline: pipeline, viewModel: center,
                    selectionColor: NSColor(appearance.selectionColor),
                    isVisible: isGrid && !photos.isEmpty
                )
                .opacity(isGrid && !photos.isEmpty ? 1 : 0)
                .allowsHitTesting(isGrid && !photos.isEmpty)
                if photos.isEmpty {
                    emptyStateForCurrentFilter
                } else if !isGrid {
                    SingleView(
                        photo: center.anchorPhoto,
                        neighbors: center.anchorNeighbors,
                        pipeline: pipeline
                    )
                }
            }
            .task(id: photos.count) {
                guard !photos.isEmpty else { return }
                await PerfProbe.runIfRequested(
                    photos: photos, viewModel: center, pipeline: pipeline,
                    controller: controller
                )
            }
        } else {
            emptyStateForCurrentFilter
        }
    }

    @ViewBuilder
    private var emptyStateForCurrentFilter: some View {
        if controller.snapshot?.photos.isEmpty ?? true {
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

/// A 1 pt divider in the panel material with a wider invisible grab area.
/// `direction` is +1 when dragging right widens the pane (sidebar) and -1
/// when it narrows it (inspector); `commit` runs on drag end.
private struct PaneDivider: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    let direction: CGFloat
    let commit: () -> Void

    /// Width captured at drag start; the drag applies its cumulative delta.
    @State private var dragBase: CGFloat?
    @State private var hovered = false
    /// Our own push is balanced by our own pop — a hover exit during a drag
    /// beyond the strip, or the strip disappearing under the pointer (panel
    /// toggle), must never leave an unbalanced cursor stack.
    @State private var cursorPushed = false

    var body: some View {
        Color.clear
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hovered = inside
                        // Keep the resize cursor while a drag runs past the strip.
                        if inside { pushCursor() } else if dragBase == nil { popCursor() }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                if dragBase == nil { dragBase = width }
                                pushCursor()
                                let proposed = dragBase! + direction * value.translation.width
                                width = min(range.upperBound, max(range.lowerBound, proposed))
                            }
                            .onEnded { _ in
                                dragBase = nil
                                if !hovered { popCursor() }
                                commit()
                            }
                    )
                    .onDisappear(perform: popCursor)
            }
    }

    private func pushCursor() {
        guard !cursorPushed else { return }
        cursorPushed = true
        NSCursor.resizeLeftRight.push()
    }

    private func popCursor() {
        guard cursorPushed else { return }
        cursorPushed = false
        NSCursor.pop()
    }
}

/// Bottom bar per spec §9.6 — mode switch in both modes; search, slider and
/// sort in grid mode only. The search filter stays active across the mode
/// change, so single mode names it (with the position among the matches) —
/// otherwise the filter would invisibly truncate the list (C6).
///
/// Its own view (not a MainWindow computed property) so Observation scopes
/// the invalidation: reading `searchText`/`columnCount` inside
/// `MainWindow.body` re-ran the whole window — and with it the grid's
/// `updateNSView` (a 50k-id sweep) — on every keystroke and slider tick.
private struct BottomBar: View {
    let center: CenterViewModel
    let controller: LibraryController

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content
        }
    }

    private var content: some View {
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
                SearchField(center: center, controller: controller)

                Spacer()

                // No step: — a stepped macOS slider draws tick marks; the
                // binding rounds to whole columns anyway. Inverted (11 − n):
                // sliding right means fewer columns, i.e. bigger thumbnails.
                Slider(
                    value: Binding(
                        get: { Double(11 - center.columnCount) },
                        set: { center.columnCount = 11 - Int($0.rounded()) }
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
}

// MARK: Search (spec §11.3, C6/U5, Q21 via the focused-text-field pass-through)

/// Same visual recipe as the inspector's Add Keyword field (`roundedFieldChrome`).
private struct SearchField: View {
    let center: CenterViewModel
    let controller: LibraryController

    @FocusState private var searchFocused: Bool
    /// Closed on accept/submit even though text is still present (spec §11.3).
    @State private var showSearchSuggestions = false
    /// Set when the search text changes programmatically (accepted suggestion)
    /// so the text-change observer keeps the dropdown closed.
    @State private var suppressNextSuggestionOpen = false

    private var searchSuggestions: [String] {
        // The vocabulary mirror, not `snapshot` — see LibraryController.vocabulary.
        KeywordAutocomplete.suggestions(for: center.searchText, tree: controller.vocabulary.tree)
    }

    var body: some View {
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
                .onChange(of: searchFocused) { _, focused in
                    // Blur closes the dropdown too; otherwise re-focusing a
                    // submitted field reopens it without any typing.
                    if !focused { showSearchSuggestions = false }
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
        .roundedFieldChrome()
        // 200 pt per spec §9.6, but compressible — at the 400 pt minimum
        // centre width the bar must never push the mode picker out.
        .frame(minWidth: 80, idealWidth: 200, maxWidth: 200)
        .overlay(alignment: .topLeading) {
            // Visibility first — the suggestion computation walks every
            // keyword path and must not run on unrelated body passes.
            if searchFocused && showSearchSuggestions {
                let suggestions = searchSuggestions
                if !suggestions.isEmpty {
                    // Dropdown above the field (spec §11.3): clicking a
                    // suggestion replaces the search text with the full path.
                    let height = SuggestionDropdown.height(forCount: suggestions.count)
                    SuggestionDropdown(suggestions: suggestions) { path in
                        suppressNextSuggestionOpen = true
                        center.searchText = path
                        showSearchSuggestions = false
                    }
                    .frame(width: 200)
                    .offset(y: -(height + 6))
                }
            }
        }
    }
}
