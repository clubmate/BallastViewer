import AppKit

/// U58: the Dock icon's badge as a progress readout for the two long runs
/// (user request 2026-09-09): "38/3942" while auto-tagging, "8 MB/s" while
/// a backup copies. Nothing is drawn — the standard red badge only — and
/// the badge clears the moment the run ends. When both run at once the
/// auto-tagging counter wins (the backup shows in the sidebar anyway).
@MainActor
enum DockBadge {
    static var autoTagging: String? { didSet { apply() } }
    static var backup: String? { didSet { apply() } }

    /// What the Dock shows right now (nil = no badge) — the test hooks read it.
    static var current: String? { autoTagging ?? backup }

    private static func apply() {
        let text = current
        guard NSApp.dockTile.badgeLabel != text else { return }
        NSApp.dockTile.badgeLabel = text
    }

    /// "850 KB/s", "8.3 MB/s", "120 MB/s", "1.2 GB/s" — short enough for
    /// the badge (about eight characters fit).
    static func speedText(bytesPerSecond: Double) -> String {
        switch bytesPerSecond {
        case 1e9...: return String(format: "%.1f GB/s", bytesPerSecond / 1e9)
        case 10e6...: return "\(Int((bytesPerSecond / 1e6).rounded())) MB/s"
        case 1e6...: return String(format: "%.1f MB/s", bytesPerSecond / 1e6)
        default: return "\(max(1, Int((bytesPerSecond / 1e3).rounded()))) KB/s"
        }
    }
}
