import SwiftUI

/// BallastViewer ▸ About — the standard panel with the house motto as
/// credits and no build number — plus Check for Updates… (U31) right below,
/// where macOS apps keep it.
struct AboutCommands: Commands {
    let updater: AppUpdater

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About BallastViewer") {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationName: "BallastViewer",
                    // Empty build string hides the "(57)" suffix.
                    .version: "",
                    .credits: NSAttributedString(
                        string: "Talent kann man nicht wegsaufen.",
                        attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                    ),
                ])
            }
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(updater.isWorking)
        }
    }
}
