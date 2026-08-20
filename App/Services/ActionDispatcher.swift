import BallastCore
import Observation

/// Where a command came from. moveUp/moveDown are grid-only from the keyboard
/// but work in both modes via MIDI (spec §10.3/§12.5) — the one deliberate
/// per-source difference.
enum DispatchSource {
    case keyboard, menu, midi
}

/// The single dispatch point shared by keyboard, menus and (later) MIDI.
/// Handles all nineteen actions exhaustively — fixing C5, where the original's
/// `default: break` made ratingUp/ratingDown unreachable. Batch semantics (U3):
/// rating and rotation apply to the whole selection; the anchor drives display
/// and LED feedback only.
@MainActor @Observable
final class ActionDispatcher {
    @ObservationIgnored private unowned let controller: LibraryController
    @ObservationIgnored private let center: CenterViewModel

    init(controller: LibraryController, center: CenterViewModel) {
        self.controller = controller
        self.center = center
    }

    func dispatch(_ command: ActionCommand, source: DispatchSource = .keyboard) {
        // Modal shield (see LibraryController.isBusy): no catalog mutation or
        // navigation while a bulk transaction owns the catalog. Covers every
        // source — keyboard, menu and MIDI all funnel through here.
        guard !controller.isBusy else { return }
        switch command {
        case .keyword(let text):
            // C7: the resolver normalises whatever text the binding stores;
            // U3: toggles apply to the whole selection, not just the anchor.
            controller.toggleKeyword(text: text, forPhotoIds: Array(center.selection.selectedIds))
        case .app(let action):
            dispatch(action, source: source)
        }
    }

    private func dispatch(_ action: AppAction, source: DispatchSource) {
        switch action {
        case .nextPhoto:
            center.moveAnchor(by: 1)
        case .previousPhoto:
            center.moveAnchor(by: -1)
        case .moveUp:
            guard center.viewMode == .grid || source == .midi else { return }
            center.moveAnchorByRow(-1)
        case .moveDown:
            guard center.viewMode == .grid || source == .midi else { return }
            center.moveAnchorByRow(1)
        case .rotate:
            controller.rotatePhotos(ids: Array(center.selection.selectedIds))
        case .viewGrid:
            center.viewMode = .grid
        case .viewSingle:
            center.viewMode = .single
        case .toggleViewMode:
            center.viewMode.toggle()
        case .rate0, .rate1, .rate2, .rate3, .rate4, .rate5:
            let stars = action.absoluteRating!
            controller.updateRatings(ids: Array(center.selection.selectedIds)) { _ in stars }
        case .ratingUp:
            controller.updateRatings(ids: Array(center.selection.selectedIds)) { $0 + 1 }
        case .ratingDown:
            controller.updateRatings(ids: Array(center.selection.selectedIds)) { $0 - 1 }
        case .toggleLeftPanel:
            center.showLeftPanel.toggle()
        case .toggleRightPanel:
            center.showRightPanel.toggle()
        case .toggleBottomPanel:
            center.showBottomPanel.toggle()
        }
    }
}
