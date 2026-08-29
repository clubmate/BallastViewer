import Testing
@testable import BallastCore

// MARK: - Panel squeeze (spec §9.1: panes shrink to their minimum before anything clips)

struct PanelSqueezeTests {
    /// The app's real constants.
    private func squeeze(
        available: Double,
        sidebar: Double = 300, sidebarShown: Bool = true,
        inspector: Double = 350, inspectorShown: Bool = true
    ) -> PanelSqueeze.Widths {
        PanelSqueeze.effectiveWidths(
            available: available,
            sidebar: sidebar, sidebarMin: 200, sidebarShown: sidebarShown,
            inspector: inspector, inspectorMin: 250, inspectorShown: inspectorShown,
            centerMin: 400, dividerWidth: 1
        )
    }

    @Test func wideWindowKeepsStoredWidths() {
        #expect(squeeze(available: 1400) == .init(sidebar: 300, inspector: 350))
        // Exact fit: 300 + 1 + 400 + 1 + 350.
        #expect(squeeze(available: 1052) == .init(sidebar: 300, inspector: 350))
    }

    @Test func inspectorShrinksFirst() {
        // 52 missing: all of it comes out of the inspector.
        #expect(squeeze(available: 1000) == .init(sidebar: 300, inspector: 298))
        // Inspector bottoms out at its minimum before the sidebar gives way.
        #expect(squeeze(available: 952) == .init(sidebar: 300, inspector: 250))
    }

    @Test func sidebarShrinksSecond() {
        // 152 missing: inspector gives 100 (to its floor), sidebar the rest.
        #expect(squeeze(available: 900) == .init(sidebar: 248, inspector: 250))
    }

    @Test func floorsHoldBelowMinimumFit() {
        // Even narrower than both floors + centerMin: panels stay at their
        // minimums; the centre absorbs the remainder instead of clipping.
        #expect(squeeze(available: 800) == .init(sidebar: 200, inspector: 250))
    }

    @Test func hiddenPanelsTakeNoSpace() {
        #expect(squeeze(available: 700, inspectorShown: false)
            == .init(sidebar: 299, inspector: 0))
        #expect(squeeze(available: 600, sidebarShown: false)
            == .init(sidebar: 0, inspector: 250))
        #expect(squeeze(available: 500, sidebarShown: false, inspectorShown: false)
            == .init(sidebar: 0, inspector: 0))
    }

    @Test func storedWidthBelowFloorIsNeverWidened() {
        // A stored width already at/below the floor must not be pushed up.
        #expect(squeeze(available: 700, sidebar: 200, inspector: 250)
            == .init(sidebar: 200, inspector: 250))
    }
}
