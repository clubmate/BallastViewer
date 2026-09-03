import Foundation

/// U49: one-shot removal of what the CLIP-based auto-tagging (U48) left on
/// disk and in the defaults — the app no longer knows those paths exist.
enum LegacyAICleanup {
    private static let markerKey = "legacyAICleanupDone"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: markerKey) else { return }
        defaults.set(true, forKey: markerKey)
        let files = FileManager.default
        let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = files.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        for url in [
            support.appendingPathComponent("BallastViewer/Models/MobileCLIP-S2", isDirectory: true),
            caches.appendingPathComponent("Embeddings", isDirectory: true),
        ] {
            try? files.removeItem(at: url)
        }
        for key in ["aiSuggestionThreshold", "aiMatchThreshold", "aiPrototypeLearning"] {
            defaults.removeObject(forKey: key)
        }
    }
}
