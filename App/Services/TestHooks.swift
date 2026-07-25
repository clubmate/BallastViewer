import AppKit
import BallastCore

/// Headless lifecycle checks, driven by environment variables so acceptance
/// criteria can be verified from the CLI (the sandboxed container's temp
/// directory is used for test libraries). Debug builds only; inert unless
/// BV_TEST is set.
///
/// Hooks: BV_TEST_CREATE=<name> · BV_TEST_OPEN=<name> · BV_TEST_IMPORT=<abs path>
/// (twice with BV_TEST_RESCAN=1) · BV_TEST_NONRECURSIVE=1 · BV_TEST_REMOVE=<abs path>
/// · BV_TEST_CLOSE=1 · BV_TEST_QUIT=1
enum TestHooks {
    @MainActor
    static func runIfRequested(_ controller: LibraryController) async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["BV_TEST"] != nil else { return }

        if let name = env["BV_TEST_CREATE"] {
            let url = testURL(named: name)
            try? FileManager.default.removeItem(at: url)
            controller.createLibrary(at: url)
        }
        if let name = env["BV_TEST_OPEN"] {
            controller.openLibrary(at: testURL(named: name))
        }
        if let path = env["BV_TEST_IMPORT"] {
            let folderURL = URL(fileURLWithPath: path, isDirectory: true)
            let recursive = env["BV_TEST_NONRECURSIVE"] == nil
            await controller.importFolders([folderURL], recursive: recursive)
            printImportState(controller, label: "import")
            if env["BV_TEST_RESCAN"] != nil {
                await controller.importFolders([folderURL], recursive: recursive)
                printImportState(controller, label: "rescan")
            }
        }
        if let path = env["BV_TEST_REMOVE"] {
            if let folder = controller.snapshot?.folders.first(where: { $0.path == path }) {
                await controller.removeFolder(folder)
            } else {
                controller.errorMessage = "BV_TEST_REMOVE: no folder registered at \(path)"
            }
            printImportState(controller, label: "remove")
        }

        print(
            "BVTEST opened=\(controller.libraryURL?.lastPathComponent ?? "none")",
            "recents=\(controller.recentLibraries.count)",
            "photos=\(controller.snapshot?.photos.count.description ?? "-")",
            "error=\(quoted(controller.errorMessage))"
        )

        if env["BV_TEST_CLOSE"] != nil {
            controller.closeLibrary()
            print("BVTEST closed opened=\(controller.libraryURL?.lastPathComponent ?? "none")")
        }
        if env["BV_TEST_QUIT"] != nil {
            exit(0)
        }
        #endif
    }

    #if DEBUG
    @MainActor
    private static func printImportState(_ controller: LibraryController, label: String) {
        let snapshot = controller.snapshot
        print(
            "BVTEST \(label)",
            "photos=\(snapshot?.photos.count.description ?? "-")",
            "folders=\(snapshot?.folders.count.description ?? "-")",
            "keywords=\(snapshot?.keywordTree.count.description ?? "-")",
            "lastBatch=\(snapshot?.meta.lastImportBatchId.map(String.init) ?? "none")",
            "info=\(quoted(controller.infoMessage))",
            "error=\(quoted(controller.errorMessage))"
        )
    }

    private static func quoted(_ message: String?) -> String {
        message.map { "\"\($0.replacingOccurrences(of: "\n", with: " "))\"" } ?? "none"
    }

    private static func testURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(LibraryDatabase.packageExtension)
    }
    #endif
}
