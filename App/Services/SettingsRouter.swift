import Observation

/// Which Settings tab is showing — lets menu items deep-link into a tab
/// ("Manage Libraries…") before opening the window.
@MainActor @Observable
final class SettingsRouter {
    enum Tab: Hashable {
        case libraries, appearance, midi, keywords, ai, shortcuts, backup
    }

    var selectedTab: Tab = .libraries
}
