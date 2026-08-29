import Foundation

/// Clamps the DISPLAYED widths of the side panels to the available window
/// width (spec §9.1 three-pane layout). The stored (user-chosen) widths are
/// never touched — they come back as soon as the window is wide enough again.
///
/// Without this, the three-pane HStack overflows when the window gets narrower
/// than sidebar + centerMin + inspector: SwiftUI centres the oversized content
/// and the sidebar slides off the left edge, unreadable.
///
/// Shrink order when space runs out: inspector first, then sidebar, each down
/// to its panel minimum (the PaneDivider range lower bound). The centre pane
/// keeps `centerMin` for as long as the panels can absorb the deficit; below
/// that (window narrower than the panel minimums + centerMin) the centre takes
/// the remainder — everything stays visible, nothing is clipped.
public enum PanelSqueeze {
    public struct Widths: Equatable, Sendable {
        public let sidebar: Double
        public let inspector: Double

        public init(sidebar: Double, inspector: Double) {
            self.sidebar = sidebar
            self.inspector = inspector
        }
    }

    public static func effectiveWidths(
        available: Double,
        sidebar: Double,
        sidebarMin: Double,
        sidebarShown: Bool,
        inspector: Double,
        inspectorMin: Double,
        inspectorShown: Bool,
        centerMin: Double,
        dividerWidth: Double
    ) -> Widths {
        var sidebarWidth = sidebarShown ? sidebar : 0
        var inspectorWidth = inspectorShown ? inspector : 0
        let dividers = (sidebarShown ? dividerWidth : 0) + (inspectorShown ? dividerWidth : 0)
        var deficit = sidebarWidth + inspectorWidth + dividers + centerMin - available
        if deficit > 0, inspectorShown {
            let cut = min(deficit, max(0, inspectorWidth - inspectorMin))
            inspectorWidth -= cut
            deficit -= cut
        }
        if deficit > 0, sidebarShown {
            let cut = min(deficit, max(0, sidebarWidth - sidebarMin))
            sidebarWidth -= cut
        }
        return Widths(sidebar: sidebarWidth, inspector: inspectorWidth)
    }
}
