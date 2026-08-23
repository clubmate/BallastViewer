import SwiftUI

/// BallastViewer ▸ About — the standard panel with the house motto as
/// credits and no build number.
struct AboutCommands: Commands {
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
        }
    }
}
