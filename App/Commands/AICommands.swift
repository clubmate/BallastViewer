import BallastCore
import SwiftUI

/// U50: the AI menu — present only while Settings ▸ AI ▸ "Enable AI
/// auto-tagging" is on. Everything auto-tagging in one place: the window
/// with the questionnaires and system prompt, the run on the selection (the
/// sidebar's right-click keeps the per-collection scope), the calibration
/// preview, and the review commands. Accept/Reject-All and "current view"
/// were removed on user request (2026-09-05): review is photo-by-photo.
///
/// Menu enablement reads only `center.hasAnchor` and the runner's phase —
/// never the snapshot — so the menu is not rebuilt on every photo mutation.
struct AICommands: Commands {
    let controller: LibraryController
    let center: CenterViewModel
    let models: VLMModelStore
    let runner: AutoTagRunner
    let settingsRouter: SettingsRouter

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private var hasAnchor: Bool { center.hasAnchor }

    var body: some Commands {
        if models.aiEnabled {
            CommandMenu("AI") {
                Button("Keyword Questionnaires…") { openWindow(id: AIWindow.id) }
                    .keyboardShortcut("k", modifiers: [.shift, .command])
                Divider()
                Button("Auto-Tag Selection") {
                    runner.run(controller: controller, models: models, photos: selectedPhotos, scopeName: "the selection")
                }
                .disabled(!hasAnchor || runner.isRunning)
                // U49: the calibration view — answers for the selection, nothing
                // applied. Capped at `AutoTagRunner.previewLimit` photos.
                Button("Preview Auto-Tagging on Selection…") {
                    runner.preview(controller: controller, models: models, photos: selectedPhotos)
                }
                .disabled(!hasAnchor || runner.isRunning)
                Button("Cancel Auto-Tagging") { runner.cancel() }
                    .disabled(!runner.isRunning)
                Divider()
                Button("Review Keywords") { center.selectSidebarItem(.pendingReview) }
                    .help("Show the photos with suggestions waiting for review")
                Button("Discard All Suggestions…") { runner.confirmingDiscard = true }
                    .disabled(runner.isRunning)
                Divider()
                Button("Model Settings…") {
                    settingsRouter.selectedTab = .ai
                    openSettings()
                }
            }
        }
    }

    private var selectedPhotos: [PhotoRecord] {
        guard let snapshot = controller.snapshot else { return [] }
        let selected = center.selection.selectedIds
        return AutoTagRunner.photos(withIds: center.visiblePhotos.map(\.id).filter { selected.contains($0) }, in: snapshot)
    }
}
