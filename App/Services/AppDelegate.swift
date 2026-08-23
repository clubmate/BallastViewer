import AppKit

/// Exists for exactly one job: draining pending write-through mutations before
/// the process exits. WAL protects against corruption on a hard kill, but a
/// rating pressed immediately before ⌘Q would otherwise race process exit and
/// silently lose its commit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Injected by BallastViewerApp at startup.
    static weak var controller: LibraryController?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = Self.controller, controller.writePipeline != nil else {
            return .terminateNow
        }
        Task { @MainActor in
            await controller.drainWrites()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
