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
            LibraryCommands(controller: controller)
            PhotoCommands(center: center, dispatcher: dispatcher, keyMap: keyMap)
            ViewCommands(center: center, dispatcher: dispatcher, keyMap: keyMap)
        }

        Settings {
            SettingsView()
                .environment(controller)
                .environment(keyMap)
                .environment(midiMap)
                .environment(appearance)
                .environment(midiService)
        }
    }
}
