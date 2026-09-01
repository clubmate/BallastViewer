import SwiftUI

@main
struct BallastViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var controller: LibraryController
    @State private var center: CenterViewModel
    @State private var sidebar: SidebarViewModel
    @State private var keyMap: KeyMapStore
    @State private var midiMap: MidiMapStore
    @State private var appearance: AppearanceStore
    @State private var dispatcher: ActionDispatcher
    @State private var shortcutMonitor: ShortcutMonitor
    @State private var midiService: MidiService
    @State private var settingsRouter = SettingsRouter()
    @State private var photoPicker = PhotoPickerModel()
    @State private var keywordPanel: KeywordPanelModel
    @State private var updater = AppUpdater()
    @State private var embeddingModels = EmbeddingModelStore()
    @State private var suggestionRunner = SuggestionRunner()

    init() {
        // U42: BEFORE anything reads UserDefaults — the sandboxed builds kept
        // all state in the container, the unsandboxed app reads ~/Library.
        SandboxMigration.runIfNeeded()
        let controller = LibraryController()
        let center = CenterViewModel(controller: controller)
        let sidebar = SidebarViewModel(controller: controller)
        let keyMap = KeyMapStore()
        let midiMap = MidiMapStore()
        let appearance = AppearanceStore()
        let dispatcher = ActionDispatcher(controller: controller, center: center)
        _controller = State(initialValue: controller)
        _center = State(initialValue: center)
        _sidebar = State(initialValue: sidebar)
        _keyMap = State(initialValue: keyMap)
        _midiMap = State(initialValue: midiMap)
        _appearance = State(initialValue: appearance)
        _dispatcher = State(initialValue: dispatcher)
        _shortcutMonitor = State(initialValue: ShortcutMonitor(keyMap: keyMap, dispatcher: dispatcher))
        _keywordPanel = State(initialValue: KeywordPanelModel(controller: controller))
        _midiService = State(initialValue: MidiService(
            midiMap: midiMap, appearance: appearance, dispatcher: dispatcher, center: center
        ))
        controller.keywordPathRenamed = { oldPath, newPath in
            keyMap.renameKeywordPath(from: oldPath, to: newPath)
            midiMap.renameKeywordPath(from: oldPath, to: newPath)
        }
        AppDelegate.controller = controller
        // U16: the picker moves files — refuse folders the open library catalogs.
        photoPicker.isFolderInOpenLibrary = { [weak controller] url in
            controller?.isFolderInOpenLibrary(url) ?? false
        }
    }

    var body: some Scene {
        // A single Window scene, deliberately not a WindowGroup: the app's
        // state (controller, selection, shortcut monitor, undo manager) is
        // strictly single-window — File ▸ New Window would show a second view
        // of the same selection and steal the shortcut whitelist.
        Window("BallastViewer", id: "main") {
            MainWindow()
                .environment(controller)
                .environment(center)
                .environment(sidebar)
                .environment(appearance)
                .environment(keywordPanel)
                .environment(updater)
                .environment(embeddingModels)
                .environment(suggestionRunner)
                .background(PhotoPickerAutoOpen())
                .task {
                    await TestHooks.runIfRequested(
                        controller, center: center, sidebar: sidebar,
                        dispatcher: dispatcher, keyMap: keyMap, midiMap: midiMap,
                        models: embeddingModels
                    )
                }
        }
        .commands {
            AboutCommands(updater: updater)
            // No File menu by design: the single Window scene has nothing to
            // put there. ⌘W lives in the app menu so Settings can still be closed.
            CommandGroup(after: .appSettings) {
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w")
            }
            LibraryCommands(controller: controller, settingsRouter: settingsRouter)
            PhotoCommands(center: center, dispatcher: dispatcher, keyMap: keyMap)
            ViewCommands(center: center, dispatcher: dispatcher, keyMap: keyMap)
        }

        // Standalone first-pass selection utility — shares nothing with the
        // library window except the image surface.
        Window("BallastPicker", id: "photoPicker") {
            PhotoPickerWindow(model: photoPicker)
        }
        .defaultSize(width: 1100, height: 750)

        Settings {
            SettingsView()
                .environment(controller)
                .environment(center)
                .environment(keyMap)
                .environment(midiMap)
                .environment(appearance)
                .environment(midiService)
                .environment(settingsRouter)
                .environment(embeddingModels)
                .environment(suggestionRunner)
        }
    }
}

/// Debug hook: `BV_TEST_PICKER_ROOT` opens the picker window at launch so it
/// can be checked headlessly (the open panel is unreachable under the sandbox).
private struct PhotoPickerAutoOpen: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["BV_TEST_PICKER_ROOT"] != nil {
                openWindow(id: "photoPicker")
            }
            #endif
        }
    }
}
