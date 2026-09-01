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
        case preparing
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

    func cancel() {
        task?.cancel()
    }

    func run(controller: LibraryController, models: EmbeddingModelStore, threshold: Float) {
        guard !isRunning else { return }
        guard let snapshot = controller.snapshot, let thumbnails = controller.thumbnails else {
            phase = .failed("Open a library first.")
            return
        }
        guard let service = models.service() else {
            phase = .failed("The model is not ready — download it above.")
            return
        }
        let described = snapshot.keywordTree.allRecords
            .filter { $0.aiDescription != nil && $0.id != nil }
        guard !described.isEmpty else {
            phase = .failed("No keyword has a description yet.")
            return
        }
        summary = nil
        phase = .preparing
        // The run scores against a point-in-time copy; `applySuggestions`
        // re-checks every pair against the LIVE snapshot, so edits made while
        // the run is going can only remove suggestions, never corrupt state.
        let rejected = controller.fetchRejectedSuggestionPairs()
        let photos = snapshot.photos
        let tree = snapshot.keywordTree
        let libraryUUID = snapshot.meta.libraryUUID
        let confirmedByPhoto = snapshot.keywordIdsByPhoto
        let pendingByPhoto = snapshot.pendingKeywordIdsByPhoto

        task = Task { [weak self, weak controller] in
            do {
                var specs: [KeywordScoringSpec] = []
                for record in described {
                    try Task.checkCancellation()
                    let embedding = try await service.textEmbedding(
                        AISettingsView.promptText(for: record.aiDescription ?? "")
                    )
                    specs.append(KeywordScoringSpec(keywordId: record.id!, textEmbedding: embedding))
                }
                let store = try EmbeddingStore(libraryUUID: libraryUUID)

                var found = 0
                var done = 0
                var batch: [Int64: [Float]] = [:]
                var batchSkip = Set<PhotoKeywordPair>()

                @MainActor func flush() {
                    guard !batch.isEmpty else { return }
                    let suggestions = SuggestionEngine.suggestions(
                        photoEmbeddings: batch,
                        specs: specs,
                        threshold: threshold,
                        skip: batchSkip.union(rejected)
                    )
                    if !suggestions.isEmpty {
                        controller?.applySuggestions(suggestions.map(\.pair))
                        found += suggestions.count
                    }
                    batch.removeAll(keepingCapacity: true)
                    batchSkip.removeAll(keepingCapacity: true)
                }

                for photo in photos {
                    guard !Task.isCancelled else { break }
                    guard let id = photo.id else { continue }
                    self?.phase = .scanning(done: done, total: photos.count, found: found)
                    done += 1
                    let mtime = EmbeddingStore.mtime(of: photo.path)
                    var vector = try await store.embedding(
                        forPath: photo.path, mtime: mtime,
                        modelVersion: EmbeddingModelStore.modelVersion
                    )
                    if vector == nil {
                        guard let box = await thumbnails.thumbnail(forPath: photo.path, longEdge: 256)
                        else { continue }
                        let fresh = try await service.imageEmbedding(box, orientation: photo.orientation)
                        try await store.store(
                            fresh, forPath: photo.path, mtime: mtime,
                            modelVersion: EmbeddingModelStore.modelVersion
                        )
                        vector = fresh
                    }
                    guard let vector else { continue }
                    batch[id] = vector
                    for keywordId in (confirmedByPhoto[id] ?? []).union(pendingByPhoto[id] ?? []) {
                        batchSkip.insert(PhotoKeywordPair(photoId: id, keywordId: keywordId))
                    }
                    if batch.count >= Self.batchSize {
                        flush()
                    }
                }
                flush()
                let cancelled = Task.isCancelled
                self?.summary = cancelled
                    ? "Cancelled after \(done) of \(photos.count) photos — \(found) suggestion\(found == 1 ? "" : "s") so far."
                    : "\(found) suggestion\(found == 1 ? "" : "s") across \(photos.count) photos. Review them via the pending chips in the inspector."
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
