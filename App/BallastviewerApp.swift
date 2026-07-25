import SwiftUI

@main
struct BallastviewerApp: App {
    @State private var controller = LibraryController()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(controller)
                .task { await TestHooks.runIfRequested(controller) }
        }
        .commands {
            LibraryCommands(controller: controller)
        }
    }
}
