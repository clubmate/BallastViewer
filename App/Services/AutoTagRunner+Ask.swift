import BallastCore
import CoreGraphics
import Foundation
import Observation

/// U54: "Ask Model on Selection…" — a free question to the vision-language
/// model about the selected photos, answered in prose, nothing assigned and
/// nothing cached. The way to find out WHAT the model sees ("Are two people
/// greeting each other? How can you tell?") before the question is turned
/// into a questionnaire. The model is loaded when the sheet opens and kept
/// until it closes, so the second question costs no reload; the run
/// settings (thinking, full resolution) apply, the system prompt is the
/// prose one (`VLMPrompt.askSystemPrompt`), not the JSON questionnaire one.
extension AutoTagRunner {
    struct AskPhoto: Identifiable, Sendable {
        var id: Int64
        var path: String
        var filename: String
        var orientation: Int
    }

    struct AskAnswer: Identifiable, Sendable {
        /// The photo's id.
        var id: Int64
        var text: String
        /// The `<think>` trace when thinking is on.
        var thinking: String?
    }

    /// One question with its answers, filling in photo by photo.
    struct AskRound: Identifiable, Sendable {
        let id = UUID()
        var question: String
        var answers: [AskAnswer] = []
        var isRunning = true
    }

    @Observable
    final class AskState: Identifiable {
        let id = UUID()
        let photos: [AskPhoto]
        let modelTitle: String
        /// Newest first — the round being answered is the first one.
        var rounds: [AskRound] = []
        var isLoadingModel = false
        var loadProgress: Double = 0
        var error: String?
        /// Decoded, upright images per photo — decoded once per session.
        @ObservationIgnored var images: [Int64: CGImageBox] = [:]
        /// The service holding the loaded model — unloaded when the session closes.
        @ObservationIgnored let service: VLMService

        init(photos: [AskPhoto], modelTitle: String, service: VLMService) {
            self.photos = photos
            self.modelTitle = modelTitle
            self.service = service
        }

        var isAnswering: Bool { rounds.first?.isRunning ?? false }
        var isBusy: Bool { isLoadingModel || isAnswering }
    }

    /// Photos per session — the same cap as the preview.
    static var askLimit: Int { previewLimit }

    /// Token budget of a prose answer (thinking on: the thinking budget).
    static let askMaxTokens = 512

    /// Opens the session for `photos` (capped) and starts loading the model.
    func startAsk(controller: LibraryController, models: VLMModelStore, photos: [PhotoRecord]) {
        guard !isRunning, preview == nil, ask == nil else { return }
        let photos = Array(photos.prefix(Self.askLimit)).compactMap { photo -> AskPhoto? in
            guard let id = photo.id else { return nil }
            return AskPhoto(id: id, path: photo.path, filename: (photo.path as NSString).lastPathComponent, orientation: photo.orientation)
        }
        let state = AskState(photos: photos, modelTitle: models.selected?.title ?? "", service: models.service)
        ask = state
        guard controller.snapshot != nil else {
            state.error = "Open a library first."
            return
        }
        guard let model = models.selected, models.isSelectedReady else {
            state.error = "The AI model is not downloaded yet — see Settings ▸ AI."
            return
        }
        guard !photos.isEmpty else {
            state.error = "Select at least one photo."
            return
        }
        let service = models.service
        let loadId = model.id
        state.isLoadingModel = true
        askTask = Task {
            do {
                try await service.load(modelId: loadId) { [weak self] fraction in
                    Task { @MainActor in self?.ask?.loadProgress = fraction }
                }
            } catch is CancellationError {
            } catch {
                state.error = error.localizedDescription
            }
            state.isLoadingModel = false
        }
    }

    /// Asks `question` about every photo of the session, one after another.
    /// Allowed while the model is still loading — the question waits for
    /// the load instead of being dropped (Return right after opening).
    func ask(_ question: String, controller: LibraryController, models: VLMModelStore) {
        guard let state = ask, !state.isAnswering, state.error == nil else { return }
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, let thumbnails = controller.thumbnails, let model = models.selected else { return }
        let round = AskRound(question: question)
        state.rounds.insert(round, at: 0)
        let roundId = round.id
        let service = models.service
        let loadId = model.id
        let thinking = UserDefaults.standard.bool(forKey: AISettingsView.thinkingKey)
        let fullResolution = UserDefaults.standard.bool(forKey: AISettingsView.fullResolutionKey)
        let systemPrompt = VLMPrompt.askSystemPrompt
        let photos = state.photos
        let pendingLoad = askTask
        askTask = Task {
            func update(_ change: (inout AskRound) -> Void) {
                guard let index = state.rounds.firstIndex(where: { $0.id == roundId }) else { return }
                change(&state.rounds[index])
            }
            // The sheet's own load may still be going — two concurrent loads
            // of the same model would load it twice.
            await pendingLoad?.value
            do {
                // No-op when the sheet's load finished; a retry when it failed.
                try await service.load(modelId: loadId) { _ in }
                for photo in photos {
                    try Task.checkCancellation()
                    if state.images[photo.id] == nil {
                        let box = fullResolution
                            ? await thumbnails.originalImage(forPath: photo.path)
                            : await thumbnails.thumbnail(forPath: photo.path, longEdge: VLMService.imageLongEdge)
                        guard let box else {
                            update { $0.answers.append(AskAnswer(id: photo.id, text: "The photo could not be decoded.")) }
                            continue
                        }
                        state.images[photo.id] = CGImageBox(image: UprightImage.make(box.image, orientation: photo.orientation))
                    }
                    let reply = try await service.answer(
                        image: state.images[photo.id]!.image, systemPrompt: systemPrompt, userPrompt: question,
                        thinking: thinking, fullResolution: fullResolution, maxTokens: Self.askMaxTokens
                    )
                    try Task.checkCancellation()
                    let split = VLMPrompt.splitThinking(reply)
                    let text = split.answer.isEmpty
                        ? (split.thinking == nil ? "(no answer)" : "(the thinking budget ran out before an answer)")
                        : split.answer
                    update { $0.answers.append(AskAnswer(id: photo.id, text: text, thinking: split.thinking)) }
                }
            } catch is CancellationError {
            } catch {
                state.error = error.localizedDescription
            }
            update { $0.isRunning = false }
        }
    }

    /// Stops the question being answered; the session stays open.
    func cancelAsk() {
        askTask?.cancel()
    }

    /// Closes the session and gives the model's memory back.
    func dismissAsk() {
        guard let state = ask else { return }
        askTask?.cancel()
        askTask = nil
        ask = nil
        // The service serializes, so a cancelled generation ends before the
        // unload runs.
        let service = state.service
        Task { await service.unload() }
    }
}
