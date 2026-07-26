import SwiftUI

@main
struct BallastviewerApp: App {
    @State private var controller: LibraryController
    @State private var center: CenterViewModel
    @State private var keyMap: KeyMapStore
    @State private var dispatcher: ActionDispatcher
    @State private var shortcutMonitor: ShortcutMonitor

    init() {
        let controller = LibraryController()
        let center = CenterViewModel(controller: controller)
        let keyMap = KeyMapStore()
        let dispatcher = ActionDispatcher(controller: controller, center: center)
        _controller = State(initialValue: controller)
        _center = State(initialValue: center)
        _keyMap = State(initialValue: keyMap)
        _dispatcher = State(initialValue: dispatcher)
        _shortcutMonitor = State(initialValue: ShortcutMonitor(keyMap: keyMap, dispatcher: dispatcher))
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(controller)
                .environment(center)
                .task { await TestHooks.runIfRequested(controller, center: center, dispatcher: dispatcher) }
        }
        .commands {
            LibraryCommands(controller: controller)
            PhotoCommands(center: center, dispatcher: dispatcher, keyMap: keyMap)
            ViewCommands(center: center, dispatcher: dispatcher, keyMap: keyMap)
        }
    }
}
