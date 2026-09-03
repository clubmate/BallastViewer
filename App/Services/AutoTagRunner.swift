import BallastCore
import Foundation
import Observation

/// U49: the auto-tagging run. Loads the selected vision-language model,
/// shows every photo of the scope to it once per enabled profile, parses the
/// reply into keywords and hands them to `LibraryController.applySuggestions`
/// as PENDING suggestions — photo by photo, so chips appear while the run is
/// still going. Replies are cached per photo, model and questionnaire, so a
/// re-run over reviewed photos or a re-mapped answer costs no inference.
/// Lives app-wide — the run keeps going when the settings window closes.
@MainActor @Observable
final class AutoTagRunner {
    enum Phase: Equatable {
        case idle
        /// Weights coming off disk (or off the network on first use).
        case loadingModel(Double)
        case scanning(done: Int, total: Int, found: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Human-readable result of the last completed run.
    private(set) var summary: String?
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        switch phase {
        case .loadingModel, .scanning: true
        case .idle, .failed: false
        }
    }

    /// Progress is observable state — throttled so the sidebar is not
    /// re-rendered for every cache hit.
    private static let progressInterval: Duration = .milliseconds(100)

    func cancel() {
        task?.cancel()
    }

    /// Clears a failure or a finished-run summary from the sidebar section.
    func dismiss() {
        if case .failed = phase { phase = .idle }
        summary = nil
    }

    /// Runs the enabled profiles over `photos` (a smart collection's members,
    /// or the whole library from the ALL PHOTOS row).
    func run(
        controller: LibraryController,
        models: VLMModelStore,
        photos: [PhotoRecord],
        scopeName: String
    ) {
        guard !isRunning else { return }
        guard let snapshot = controller.snapshot, let thumbnails = controller.thumbnails else {
            phase = .failed("Open a library first.")
            return
        }
        let profiles = snapshot.aiProfiles.filter { $0.enabled && !$0.questions.isEmpty }
        guard !profiles.isEmpty else {
            phase = .failed("No profile is switched on — set one up in Settings ▸ AI.")
            return
        }
        guard profiles.contains(where: { !$0.keywordIds.isEmpty }) else {
            phase = .failed("No answer of the enabled profiles is mapped to a keyword yet — see Settings ▸ AI.")
            return
        }
        guard let model = models.selected, models.isSelectedReady else {
            phase = .failed("The AI model is not downloaded yet — see Settings ▸ AI.")
            return
        }
        guard !photos.isEmpty else {
            phase = .failed("“\(scopeName)” contains no photos.")
            return
        }
        summary = nil
        phase = .loadingModel(0)
        // The run scores against a point-in-time copy; `applySuggestions`
        // re-checks every pair against the LIVE snapshot, so edits made while
        // the run is going can only remove suggestions, never corrupt state.
        let rejected = controller.fetchRejectedSuggestionPairs()
        let libraryUUID = snapshot.meta.libraryUUID
        let confirmedByPhoto = snapshot.keywordIdsByPhoto
        let pendingByPhoto = snapshot.pendingKeywordIdsByPhoto
        let service = models.service
        let modelId = model.id
        let questionnaires = profiles.map { ($0, VLMPrompt.questionnaireHash(for: $0), VLMPrompt.userPrompt(for: $0)) }

        task = Task { [weak self, weak controller] in
            do {
                try await service.load(modelId: modelId) { [weak self] fraction in
                    Task { @MainActor in
                        if case .loadingModel = self?.phase { self?.phase = .loadingModel(fraction) }
                    }
                }
                let store = try await AIAnswerStore.open(libraryUUID: libraryUUID)
                var found = 0
                var done = 0
                var unanswered = 0
                var libraryChanged = false
                var lastProgress = ContinuousClock.now
                self?.phase = .scanning(done: 0, total: photos.count, found: 0)

                for photo in photos {
                    guard !Task.isCancelled, let photoId = photo.id else { break }
                    // The run belongs to ONE library: ids are per-library, so
                    // a switch mid-run ends the scan.
                    guard controller?.snapshot?.meta.libraryUUID == libraryUUID else {
                        libraryChanged = true
                        break
                    }
                    let mtime = AIAnswerStore.mtime(of: photo.path)
                    var upright: CGImageBox?
                    var keywordIds = Set<Int64>()
                    for (profile, questionnaire, userPrompt) in questionnaires {
                        var reply = try await store.reply(
                            forPath: photo.path, mtime: mtime, modelId: modelId, questionnaire: questionnaire
                        )
                        if reply == nil {
                            if upright == nil {
                                guard let box = await thumbnails.thumbnail(
                                    forPath: photo.path, longEdge: VLMService.imageLongEdge
                                ) else { break }
                                upright = CGImageBox(image: UprightImage.make(box.image, orientation: photo.orientation))
                            }
                            let fresh = try await service.answer(
                                image: upright!.image, systemPrompt: VLMPrompt.systemPrompt, userPrompt: userPrompt
                            )
                            try await store.store(
                                fresh, forPath: photo.path, mtime: mtime, modelId: modelId, questionnaire: questionnaire
                            )
                            reply = fresh
                        }
                        let parsed = VLMAnswerParser.parse(reply ?? "", profile: profile)
                        if parsed.isEmpty { unanswered += 1 }
                        keywordIds.formUnion(VLMAnswerParser.keywordIds(in: parsed))
                    }
                    done += 1
                    let skip = (confirmedByPhoto[photoId] ?? []).union(pendingByPhoto[photoId] ?? [])
                    let pairs = keywordIds.subtracting(skip)
                        .map { PhotoKeywordPair(photoId: photoId, keywordId: $0) }
                        .filter { !rejected.contains($0) }
                    if !pairs.isEmpty {
                        controller?.applySuggestions(pairs, libraryUUID: libraryUUID)
                        found += pairs.count
                    }
                    let now = ContinuousClock.now
                    if now - lastProgress >= Self.progressInterval {
                        lastProgress = now
                        self?.phase = .scanning(done: done, total: photos.count, found: found)
                    }
                }
                let cancelled = Task.isCancelled
                self?.summary = libraryChanged
                    ? "Stopped — the library changed mid-run."
                    : cancelled
                    ? "Cancelled after \(done) of \(photos.count) photos in “\(scopeName)” — \(found) suggestion\(found == 1 ? "" : "s") so far."
                    : "\(found) suggestion\(found == 1 ? "" : "s") across \(photos.count) photos in “\(scopeName)” (\(model.title))"
                        + (unanswered > 0 ? "; \(unanswered) repl\(unanswered == 1 ? "y" : "ies") could not be read" : "")
                        + "."
                self?.phase = .idle
            } catch is CancellationError {
                self?.summary = "Cancelled."
                self?.phase = .idle
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
            // Give the memory back — reloading from disk takes seconds.
            await service.unload()
        }
    }
}
