import SwiftUI

/// ballastviewer ▸ About — the standard panel, but with the name in
/// uppercase and the house motto as credits.
struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About BALLASTVIEWER") {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationName: "BALLASTVIEWER",
                    // Empty build string hides the "(57)" suffix.
                    .version: "",
                    .credits: NSAttributedString(
                        string: "talent kann man nicht wegsaufen.",
                        attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                    ),
                ])
            }
        }
    }
}
