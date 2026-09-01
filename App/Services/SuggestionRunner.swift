import BallastCore
import Foundation
import Observation

/// U48 Stage 2: the suggestion run. Embeds every library photo (cache-first),
/// scores it against all described keywords, and hands matches to
/// `LibraryController.applySuggestions` in batches so a long run surfaces
/// pending chips while it is still going. Lives app-wide — the run keeps
/// going when the settings window closes.
@MainActor @Observable
final class SuggestionRunner {
    enum Phase: Equatable {
        case idle
        /// Embedding descriptions and example photos (Stage 4 prototypes);
        /// (done, total) counts the example embeddings.
        case preparing(done: Int, total: Int)
        case scanning(done: Int, total: Int, found: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Human-readable result of the last completed run.
    private(set) var summary: String?
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        switch phase {
        case .preparing, .scanning: true
        case .idle, .failed: false
        }
    }

    private static let batchSize = 200
    /// Photos embedded concurrently: thumbnail decodes overlap the (actor-
    /// serialized) CoreML inference instead of strictly alternating with it.
    nonisolated private static let prefetchWindow = 4
    /// Progress is observable state — one update per photo would re-render
    /// the sidebar thousands of times per second on cache hits.
    private static let progressInterval: Duration = .milliseconds(100)
    /// Photos embedded to estimate the library-mean image embedding (the
    /// prototype baseline). 256 unit vectors pin a 512-dim mean well enough;
    /// they are library photos, so the scan hits the cache for them anyway.
    nonisolated private static let libraryMeanSampleSize = 256

    func cancel() {
        task?.cancel()
    }

    /// Clears a failure or a finished-run summary from the sidebar section.
    func dismiss() {
        if case .failed = phase { phase = .idle }
        summary = nil
    }

    /// The CLIP prompt for one description variant. CLIP was trained on
    /// caption-style text, so bare fragments score better wrapped in
    /// "a photo of …".
    nonisolated static func promptText(for description: String) -> String {
        let lowered = description.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lowered.hasPrefix("a photo") ? lowered : "a photo of \(lowered)"
    }

    /// One photo's embedding, cache-first — shared by the run and the example
    /// (prototype) pass.
    nonisolated static func embedding(
        for photo: PhotoRecord,
        service: EmbeddingService,
        store: EmbeddingStore,
        thumbnails: ThumbnailPipeline
    ) async throws -> [Float]? {
        let mtime = EmbeddingStore.mtime(of: photo.path)
        if let cached = try await store.embedding(
            forPath: photo.path, mtime: mtime, modelVersion: EmbeddingModelStore.modelVersion
        ) {
            return cached
        }
        guard let box = await thumbnails.thumbnail(forPath: photo.path, longEdge: 256) else {
            return nil
        }
        let fresh = try await service.imageEmbedding(box, orientation: photo.orientation)
        try await store.store(
            fresh, forPath: photo.path, mtime: mtime,
            modelVersion: EmbeddingModelStore.modelVersion
        )
        return fresh
    }

    /// A prefetch window's worth of `embedding(for:)` calls in flight at once.
    /// Order is irrelevant — the scorer batches by id.
    nonisolated static func embeddings(
        for photos: ArraySlice<PhotoRecord>,
        service: EmbeddingService,
        store: EmbeddingStore,
        thumbnails: ThumbnailPipeline
    ) async throws -> [(id: Int64, vector: [Float])] {
        try await withThrowingTaskGroup(of: (Int64, [Float]?).self) { group in
            for photo in photos {
                guard let id = photo.id else { continue }
                group.addTask {
                    (id, try await embedding(for: photo, service: service, store: store, thumbnails: thumbnails))
                }
            }
            var result: [(id: Int64, vector: [Float])] = []
            for try await (id, vector) in group {
                if let vector { result.append((id: id, vector: vector)) }
            }
            return result
        }
    }

    /// A deterministic, evenly spread sample of the library (every k-th photo
    /// in catalog order) standing in for "ordinary photos of this library" —
    /// the prototype baseline is the mean score over it. Deterministic so two
    /// runs score identically.
    nonisolated static func libraryMeanSample(_ photos: [PhotoRecord]) -> ArraySlice<PhotoRecord> {
        guard photos.count > libraryMeanSampleSize else { return photos[...] }
        let step = photos.count / libraryMeanSampleSize
        return stride(from: 0, to: photos.count, by: step).prefix(libraryMeanSampleSize)
            .map { photos[$0] }[...]
    }

    /// Stage 4: one scoring spec per described keyword — text embedding PLUS
    /// the prototype learned from the keyword's CONFIRMED carriers (manual
    /// and accepted alike; no provenance needed). The blend weight moves from
    /// description to examples as `exampleCount` grows (α = 8/(8+n), pinned
    /// by SuggestionEngineTests). The prototype is scored RELATIVE to the
    /// library: its mean cosine over a sample of the whole library (minus the
    /// keyword's own carriers) is the baseline an unrelated photo would get
    /// and is subtracted before blending — see `KeywordScoringSpec.prototypeBaseline`.
    /// Used identically by the run and the diagnostic, so calibration always
    /// shows the scores a run would use.
    nonisolated static func buildSpecs(
        snapshot: LibrarySnapshot,
        service: EmbeddingService,
        store: EmbeddingStore,
        thumbnails: ThumbnailPipeline,
        progress: (@MainActor @Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [(path: String, spec: KeywordScoringSpec)] {
        let described = snapshot.keywordTree.allRecords
            .filter { $0.aiDescription != nil && $0.id != nil }
        guard !described.isEmpty else { return [] }
        var photosById: [Int64: PhotoRecord] = [:]
        for photo in snapshot.photos {
            if let id = photo.id { photosById[id] = photo }
        }
        // Invert the confirmed map once for the described ids only.
        let describedIds = Set(described.compactMap(\.id))
        var carriersByKeyword: [Int64: [Int64]] = [:]
        for (photoId, keywordIds) in snapshot.keywordIdsByPhoto {
            for keywordId in keywordIds where describedIds.contains(keywordId) {
                carriersByKeyword[keywordId, default: []].append(photoId)
            }
        }
        // The library sample only matters when some keyword has examples;
        // a text-only setup skips the extra embeddings entirely.
        let sample = carriersByKeyword.isEmpty ? [] : libraryMeanSample(snapshot.photos)
        let exampleTotal = carriersByKeyword.values.reduce(0) { $0 + $1.count } + sample.count
        var examplesDone = 0

        var sampleEmbeddings: [(id: Int64, vector: [Float])] = []
        for start in stride(from: 0, to: sample.count, by: prefetchWindow) {
            try Task.checkCancellation()
            let chunk = sample[start ..< min(start + prefetchWindow, sample.count)]
            sampleEmbeddings.append(contentsOf: try await embeddings(
                for: chunk, service: service, store: store, thumbnails: thumbnails
            ))
            examplesDone += chunk.count
            if let progress {
                let done = examplesDone
                await MainActor.run { progress(done, exampleTotal) }
            }
        }

        var specs: [(path: String, spec: KeywordScoringSpec)] = []
        for record in described {
            try Task.checkCancellation()
            let keywordId = record.id!
            // One embedding per "|"-separated prompt variant — an "or"
            // keyword scores as the best variant, never a washed-out average.
            var textEmbeddings: [[Float]] = []
            for variant in SuggestionEngine.promptVariants(record.aiDescription ?? "") {
                textEmbeddings.append(try await service.textEmbedding(promptText(for: variant)))
            }
            var exampleEmbeddings: [[Float]] = []
            for photoId in carriersByKeyword[keywordId] ?? [] {
                try Task.checkCancellation()
                examplesDone += 1
                guard let photo = photosById[photoId] else { continue }
                if let vector = try await embedding(
                    for: photo, service: service, store: store, thumbnails: thumbnails
                ) {
                    exampleEmbeddings.append(vector)
                }
                if let progress {
                    let done = examplesDone
                    await MainActor.run { progress(done, exampleTotal) }
                }
            }
            let prototype = SuggestionEngine.prototype(of: exampleEmbeddings)
            // Ordinary photos only: the keyword's own carriers would pull the
            // baseline toward the prototype (decisive in small libraries).
            let carriers = Set(carriersByKeyword[keywordId] ?? [])
            let ordinary = sampleEmbeddings.filter { !carriers.contains($0.id) }.map(\.vector)
            specs.append((
                path: snapshot.keywordTree.path(of: keywordId),
                spec: KeywordScoringSpec(
                    keywordId: keywordId,
                    textEmbeddings: textEmbeddings,
                    prototypeEmbedding: prototype,
                    exampleCount: exampleEmbeddings.count,
                    prototypeBaseline: prototype.map {
                        SuggestionEngine.prototypeBaseline(prototype: $0, sample: ordinary)
                    } ?? 0
                )
            ))
        }
        return specs
    }

    /// Runs auto-tagging over `photos` (a smart collection's members, or the
    /// whole library from the ALL PHOTOS row). Prototype learning always uses
    /// the WHOLE library's confirmed carriers — the scope limits only what
    /// gets scanned for new suggestions.
    func run(
        controller: LibraryController,
        models: EmbeddingModelStore,
        threshold: Float,
        photos: [PhotoRecord],
        scopeName: String
    ) {
        guard !isRunning else { return }
        guard let snapshot = controller.snapshot, let thumbnails = controller.thumbnails else {
            phase = .failed("Open a library first.")
            return
        }
        guard let service = models.service() else {
            phase = .failed("The AI model is not downloaded yet — see Settings ▸ AI.")
            return
        }
        let described = snapshot.keywordTree.allRecords
            .filter { $0.aiDescription != nil && $0.id != nil }
        guard !described.isEmpty else {
            phase = .failed("No keyword has an AI prompt yet — add prompts in Settings ▸ AI.")
            return
        }
        guard !photos.isEmpty else {
            phase = .failed("“\(scopeName)” contains no photos.")
            return
        }
        summary = nil
        phase = .preparing(done: 0, total: 0)
        // The run scores against a point-in-time copy; `applySuggestions`
        // re-checks every pair against the LIVE snapshot, so edits made while
        // the run is going can only remove suggestions, never corrupt state.
        let rejected = controller.fetchRejectedSuggestionPairs()
        let libraryUUID = snapshot.meta.libraryUUID
        let confirmedByPhoto = snapshot.keywordIdsByPhoto
        let pendingByPhoto = snapshot.pendingKeywordIdsByPhoto

        task = Task { [weak self, weak controller] in
            do {
                let store = try await EmbeddingStore.open(libraryUUID: libraryUUID)
                // Stage 4: specs carry the prototype learned from each
                // keyword's confirmed carriers; their embeddings land in the
                // store, so the scan below hits the cache for them.
                let specs = try await Self.buildSpecs(
                    snapshot: snapshot,
                    service: service,
                    store: store,
                    thumbnails: thumbnails,
                    progress: { [weak self] done, total in
                        self?.phase = .preparing(done: done, total: total)
                    }
                ).map(\.spec)
                let examples = specs.reduce(0) { $0 + $1.exampleCount }

                var found = 0
                var done = 0
                var batch: [Int64: [Float]] = [:]
                var batchSkip = Set<PhotoKeywordPair>()
                var libraryChanged = false
                var lastProgress = ContinuousClock.now
                self?.phase = .scanning(done: 0, total: photos.count, found: 0)

                @MainActor func flush() {
                    guard !batch.isEmpty else { return }
                    let suggestions = SuggestionEngine.suggestions(
                        photoEmbeddings: batch,
                        specs: specs,
                        threshold: threshold,
                        skip: batchSkip.union(rejected)
                    )
                    if !suggestions.isEmpty {
                        controller?.applySuggestions(suggestions.map(\.pair), libraryUUID: libraryUUID)
                        found += suggestions.count
                    }
                    batch.removeAll(keepingCapacity: true)
                    batchSkip.removeAll(keepingCapacity: true)
                }

                for start in stride(from: 0, to: photos.count, by: Self.prefetchWindow) {
                    guard !Task.isCancelled else { break }
                    // The run belongs to ONE library: ids are per-library, so
                    // a switch mid-run ends the scan (applySuggestions drops
                    // stragglers on its own, this just stops the work).
                    guard controller?.snapshot?.meta.libraryUUID == libraryUUID else {
                        libraryChanged = true
                        break
                    }
                    let chunk = photos[start ..< min(start + Self.prefetchWindow, photos.count)]
                    let vectors = try await Self.embeddings(
                        for: chunk, service: service, store: store, thumbnails: thumbnails
                    )
                    done += chunk.count
                    for (id, vector) in vectors {
                        batch[id] = vector
                        for keywordId in (confirmedByPhoto[id] ?? []).union(pendingByPhoto[id] ?? []) {
                            batchSkip.insert(PhotoKeywordPair(photoId: id, keywordId: keywordId))
                        }
                    }
                    if batch.count >= Self.batchSize {
                        flush()
                    }
                    let now = ContinuousClock.now
                    if now - lastProgress >= Self.progressInterval {
                        lastProgress = now
                        self?.phase = .scanning(done: done, total: photos.count, found: found)
                    }
                }
                if !libraryChanged { flush() }
                let cancelled = Task.isCancelled
                self?.summary = libraryChanged
                    ? "Stopped — the library changed mid-run."
                    : cancelled
                    ? "Cancelled after \(done) of \(photos.count) photos in “\(scopeName)” — \(found) suggestion\(found == 1 ? "" : "s") so far."
                    : "\(found) suggestion\(found == 1 ? "" : "s") across \(photos.count) photos in “\(scopeName)”"
                        + (examples > 0 ? ", learned from \(examples) confirmed example\(examples == 1 ? "" : "s")" : "")
                        + "."
                self?.phase = .idle
            } catch is CancellationError {
                self?.summary = "Cancelled."
                self?.phase = .idle
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }
}
