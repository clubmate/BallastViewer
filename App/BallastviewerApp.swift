import SwiftUI

@main
struct BallastviewerApp: App {
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

    init() {
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
        _midiService = State(initialValue: MidiService(
            midiMap: midiMap, appearance: appearance, dispatcher: dispatcher, center: center
        ))
        controller.keywordPathRenamed = { oldPath, newPath in
            keyMap.renameKeywordPath(from: oldPath, to: newPath)
            midiMap.renameKeywordPath(from: oldPath, to: newPath)
        }
        AppDelegate.controller = controller
    }

    var body: some Scene {
        // A single Window scene, deliberately not a WindowGroup: the app's
        // state (controller, selection, shortcut monitor, undo manager) is
        // strictly single-window — File ▸ New Window would show a second view
        // of the same selection and steal the shortcut whitelist.
        Window("ballastviewer", id: "main") {
            MainWindow()
                .environment(controller)
                .environment(center)
                .environment(sidebar)
                .environment(appearance)
                .background(PhotoPickerAutoOpen())
                .task {
                    await TestHooks.runIfRequested(
                        controller, center: center, sidebar: sidebar,
                        dispatcher: dispatcher, keyMap: keyMap, midiMap: midiMap
                    )
                }
        }
        .commands {
            // The Window scene drops the automatic File menu entirely — bring
            // back ⌘W, which also closes the Settings window.
            CommandGroup(replacing: .saveItem) {
                Button("Close") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w")
            }
            LibraryCommands(controller: controller, settingsRouter: settingsRouter)
            PhotoCommands(center: center, dispatcher: dispatcher, keyMap: keyMap)
            ViewCommands(center: center, dispatcher: dispatcher, keyMap: keyMap)
            PhotoPickerCommands()
        }

        // Standalone first-pass selection utility — shares nothing with the
        // library window except the image surface.
        Window("Photo Picker", id: "photoPicker") {
            PhotoPickerWindow(model: photoPicker)
        }
        .defaultSize(width: 1100, height: 750)

        Settings {
            SettingsView()
                .environment(controller)
                .environment(keyMap)
                .environment(midiMap)
                .environment(appearance)
                .environment(midiService)
                .environment(settingsRouter)
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
