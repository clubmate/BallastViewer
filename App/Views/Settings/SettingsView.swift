import SwiftUI

/// Fixed 600×500 settings window (spec §9.9). Keywords is the step-8 tab;
/// Appearance and Shortcuts arrive in step 9.
struct SettingsView: View {
    var body: some View {
        TabView {
            KeywordsSettingsView()
                .tabItem { Label("Keywords", systemImage: "tag") }
        }
        .frame(width: 600, height: 500)
    }
}
