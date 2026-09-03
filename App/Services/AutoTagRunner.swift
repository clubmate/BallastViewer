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
        /// `remaining` is the time-left estimate in seconds (nil until a
        /// few photos have been timed).
        case scanning(done: Int, total: Int, found: Int, remaining: TimeInterval?)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Human-readable result of the last completed run.
    private(set) var summary: String?
    private var task: Task<Void, Never>?

    // MARK: Preview (calibration)

    struct PreviewAnswer: Sendable {
        var question: String
        var value: String
        var keywordPath: String?
    }

    struct PreviewReply: Sendable {
        var profileName: String
        var raw: String
        var answers: [PreviewAnswer]
    }

    struct PreviewItem: Identifiable, Sendable {
        var id: Int64
        var path: String
        var filename: String
        var replies: [PreviewReply]
    }

    /// The model's answers for a few selected photos, shown but never
    /// applied — the tool for tuning question wording before a long run.
    @Observable
    final class PreviewState: Identifiable {
        let id = UUID()
        var items: [PreviewItem] = []
        var done = 0
        let total: Int
        var isRunning = true
        var error: String?

        init(total: Int) { self.total = total }
    }

    private(set) var preview: PreviewState?

    /// At most this many photos per preview — enough to judge wording.
    static let previewLimit = 24

    func dismissPreview() {
        guard preview?.isRunning != true else { return }
        preview = nil
    }

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
        // The cache key names the installed snapshot too: a re-quantised
        // `main` under the same repository id answers differently.
        let modelId = model.id + "@" + (VLMModelStore.installedRevision(model.id) ?? "main")
        let loadId = model.id
        // Rejections per photo — with confirmed and pending, the "already
        // decided" set that lets a fully reviewed photo skip inference.
        var rejectedByPhoto: [Int64: Set<Int64>] = [:]
        for pair in rejected { rejectedByPhoto[pair.photoId, default: []].insert(pair.keywordId) }
        // Run settings (Settings ▸ AI): system prompt, thinking, resolution —
        // part of the reply-cache key, so flipping one re-asks the model.
        let systemPrompt = AISettingsView.currentSystemPrompt
        let thinking = UserDefaults.standard.bool(forKey: AISettingsView.thinkingKey)
        let fullResolution = UserDefaults.standard.bool(forKey: AISettingsView.fullResolutionKey)
        let settingsHash = VLMPrompt.settingsHash(
            systemPrompt: systemPrompt, thinking: thinking, fullResolution: fullResolution
        )
        let questionnaires = profiles.map {
            ($0, VLMPrompt.questionnaireHash(for: $0) + "|" + settingsHash, VLMPrompt.userPrompt(for: $0))
        }

        task = Task { [weak self, weak controller] in
            // A 30k-photo run takes days; the Mac must not doze off mid-way.
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated], reason: "Auto-tagging photos"
            )
            defer { ProcessInfo.processInfo.endActivity(activity) }
            do {
                try await service.load(modelId: loadId) { [weak self] fraction in
                    Task { @MainActor in
                        if case .loadingModel = self?.phase { self?.phase = .loadingModel(fraction) }
                    }
                }
                let store = try await AIAnswerStore.open(libraryUUID: libraryUUID)
                var found = 0
                var done = 0
                var unanswered = 0
                var unreadable = 0
                var skipped = 0
                var libraryChanged = false
                var lastProgress = ContinuousClock.now
                // Time-left estimate: an exponential moving average of the
                // per-photo duration (cache hits count as ~0, so a re-run
                // over reviewed photos shrinks the estimate fast).
                var averageSeconds: Double = 0
                var timed = 0
                var remaining: TimeInterval?
                self?.phase = .scanning(done: 0, total: photos.count, found: 0, remaining: nil)

                for photo in photos {
                    let photoStart = ContinuousClock.now
                    guard !Task.isCancelled, let photoId = photo.id else { break }
                    // The run belongs to ONE library: ids are per-library, so
                    // a switch mid-run ends the scan.
                    guard controller?.snapshot?.meta.libraryUUID == libraryUUID else {
                        libraryChanged = true
                        break
                    }
                    let mtime = AIAnswerStore.mtime(of: photo.path)
                    let decided = (confirmedByPhoto[photoId] ?? [])
                        .union(pendingByPhoto[photoId] ?? [])
                        .union(rejectedByPhoto[photoId] ?? [])
                    var upright: CGImageBox?
                    var keywordIds = Set<Int64>()
                    var imageMissing = false
                    for (profile, questionnaire, userPrompt) in questionnaires {
                        // Every keyword this profile could assign is already
                        // confirmed, pending or rejected on the photo — asking
                        // again could not change anything.
                        if profile.keywordIds.isSubset(of: decided) {
                            skipped += 1
                            continue
                        }
                        var reply = try await store.reply(
                            forPath: photo.path, mtime: mtime, modelId: modelId, questionnaire: questionnaire
                        )
                        if reply == nil {
                            if upright == nil {
                                // Full resolution = the decoded original (the
                                // single view's cache, ≤ 2K previews by the
                                // image profile); otherwise the 768 bucket.
                                let box = fullResolution
                                    ? await thumbnails.originalImage(forPath: photo.path)
                                    : await thumbnails.thumbnail(forPath: photo.path, longEdge: VLMService.imageLongEdge)
                                guard let box else {
                                    imageMissing = true
                                    break
                                }
                                upright = CGImageBox(image: UprightImage.make(box.image, orientation: photo.orientation))
                            }
                            let fresh = try await service.answer(
                                image: upright!.image, systemPrompt: systemPrompt, userPrompt: userPrompt,
                                thinking: thinking, fullResolution: fullResolution
                            )
                            try Task.checkCancellation()
                            // Only a reply that answered something is worth
                            // keeping: an exhausted thinking budget or a
                            // garbled reply must be re-asked next time, not
                            // cached as "no answer" forever.
                            if !VLMAnswerParser.parse(fresh, profile: profile).isEmpty {
                                try await store.store(
                                    fresh, forPath: photo.path, mtime: mtime, modelId: modelId, questionnaire: questionnaire
                                )
                            }
                            reply = fresh
                        }
                        let parsed = VLMAnswerParser.parse(reply ?? "", profile: profile)
                        if parsed.isEmpty { unanswered += 1 }
                        keywordIds.formUnion(VLMAnswerParser.keywordIds(in: parsed))
                    }
                    if imageMissing { unreadable += 1 }
                    done += 1
                    let elapsed = ContinuousClock.now - photoStart
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    timed += 1
                    averageSeconds = timed == 1 ? seconds : averageSeconds * 0.85 + seconds * 0.15
                    remaining = timed >= 3 ? averageSeconds * Double(photos.count - done) : nil
                    let pairs = keywordIds.subtracting(decided)
                        .map { PhotoKeywordPair(photoId: photoId, keywordId: $0) }
                    if !pairs.isEmpty {
                        controller?.applySuggestions(pairs, libraryUUID: libraryUUID)
                        found += pairs.count
                    }
                    let now = ContinuousClock.now
                    if now - lastProgress >= Self.progressInterval {
                        lastProgress = now
                        self?.phase = .scanning(done: done, total: photos.count, found: found, remaining: remaining)
                    }
                }
                let cancelled = Task.isCancelled
                self?.summary = libraryChanged
                    ? "Stopped — the library changed mid-run."
                    : cancelled
                    ? "Cancelled after \(done) of \(photos.count) photos in “\(scopeName)” — \(found) suggestion\(found == 1 ? "" : "s") so far."
                    : "\(found) suggestion\(found == 1 ? "" : "s") across \(photos.count) photos in “\(scopeName)” (\(model.title))"
                        + (unanswered > 0 ? "; \(unanswered) repl\(unanswered == 1 ? "y" : "ies") could not be read" : "")
                        + (unreadable > 0 ? "; \(unreadable) photo\(unreadable == 1 ? "" : "s") could not be decoded" : "")
                        + (skipped > 0 ? "; \(skipped) already fully reviewed" : "")
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

    /// Asks every enabled profile about `photos` (capped at `previewLimit`)
    /// and shows the answers; nothing is applied. Uses and fills the reply
    /// cache like a run, so a following run over the same photos is free.
    func preview(controller: LibraryController, models: VLMModelStore, photos: [PhotoRecord]) {
        guard !isRunning, preview == nil else { return }
        guard let snapshot = controller.snapshot, let thumbnails = controller.thumbnails else { return }
        let profiles = snapshot.aiProfiles.filter { $0.enabled && !$0.questions.isEmpty }
        let photos = Array(photos.prefix(Self.previewLimit))
        let state = PreviewState(total: photos.count)
        preview = state
        guard !profiles.isEmpty else {
            state.error = "No profile is switched on — set one up in Settings ▸ AI."
            state.isRunning = false
            return
        }
        guard let model = models.selected, models.isSelectedReady else {
            state.error = "The AI model is not downloaded yet — see Settings ▸ AI."
            state.isRunning = false
            return
        }
        guard !photos.isEmpty else {
            state.error = "Select at least one photo."
            state.isRunning = false
            return
        }
        phase = .loadingModel(0)
        let service = models.service
        let modelId = model.id + "@" + (VLMModelStore.installedRevision(model.id) ?? "main")
        let loadId = model.id
        let systemPrompt = AISettingsView.currentSystemPrompt
        let thinking = UserDefaults.standard.bool(forKey: AISettingsView.thinkingKey)
        let fullResolution = UserDefaults.standard.bool(forKey: AISettingsView.fullResolutionKey)
        let settingsHash = VLMPrompt.settingsHash(
            systemPrompt: systemPrompt, thinking: thinking, fullResolution: fullResolution
        )
        let questionnaires = profiles.map {
            ($0, VLMPrompt.questionnaireHash(for: $0) + "|" + settingsHash, VLMPrompt.userPrompt(for: $0))
        }
        let tree = snapshot.keywordTree
        let libraryUUID = snapshot.meta.libraryUUID

        task = Task { [weak self] in
            do {
                try await service.load(modelId: loadId) { [weak self] fraction in
                    Task { @MainActor in
                        if case .loadingModel = self?.phase { self?.phase = .loadingModel(fraction) }
                    }
                }
                self?.phase = .idle
                let store = try await AIAnswerStore.open(libraryUUID: libraryUUID)
                for photo in photos {
                    try Task.checkCancellation()
                    guard let photoId = photo.id else { continue }
                    let mtime = AIAnswerStore.mtime(of: photo.path)
                    var upright: CGImageBox?
                    var replies: [PreviewReply] = []
                    for (profile, questionnaire, userPrompt) in questionnaires {
                        var reply = try await store.reply(
                            forPath: photo.path, mtime: mtime, modelId: modelId, questionnaire: questionnaire
                        )
                        if reply == nil {
                            if upright == nil {
                                let box = fullResolution
                                    ? await thumbnails.originalImage(forPath: photo.path)
                                    : await thumbnails.thumbnail(forPath: photo.path, longEdge: VLMService.imageLongEdge)
                                guard let box else { break }
                                upright = CGImageBox(image: UprightImage.make(box.image, orientation: photo.orientation))
                            }
                            let fresh = try await service.answer(
                                image: upright!.image, systemPrompt: systemPrompt, userPrompt: userPrompt,
                                thinking: thinking, fullResolution: fullResolution
                            )
                            try Task.checkCancellation()
                            if !VLMAnswerParser.parse(fresh, profile: profile).isEmpty {
                                try await store.store(
                                    fresh, forPath: photo.path, mtime: mtime, modelId: modelId, questionnaire: questionnaire
                                )
                            }
                            reply = fresh
                        }
                        let parsed = VLMAnswerParser.parse(reply ?? "", profile: profile)
                        let answers = profile.questions.compactMap { question -> PreviewAnswer? in
                            guard let id = question.id, let answer = parsed[id] else { return nil }
                            return PreviewAnswer(
                                question: question.text,
                                value: answer.value,
                                keywordPath: answer.keywordId.flatMap { tree.node($0) != nil ? tree.path(of: $0) : nil }
                            )
                        }
                        replies.append(PreviewReply(profileName: profile.name, raw: reply ?? "", answers: answers))
                    }
                    state.items.append(PreviewItem(
                        id: photoId, path: photo.path,
                        filename: (photo.path as NSString).lastPathComponent, replies: replies
                    ))
                    state.done += 1
                }
            } catch is CancellationError {
                state.error = "Cancelled."
            } catch {
                state.error = error.localizedDescription
            }
            self?.phase = .idle
            state.isRunning = false
            await service.unload()
        }
    }
}
