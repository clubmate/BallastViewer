import BallastCore
import Foundation
import GRDB

/// The two manual metadata sync commands (spec §6.4): both process every photo
/// in the library with bounded concurrency, both report with *distinct* wording
/// (U12), and both list unreadable files instead of hiding them (Q27).
extension LibraryController {
    /// One photo's sync job: the library's authoritative values plus the path.
    private struct SyncJob: Sendable {
        var photoId: Int64
        var path: String
        var libraryValues: PhotoFileMetadata
    }

    private struct FileReadResult: Sendable {
        var job: SyncJob
        /// nil = unreadable (skipped, reported per Q27).
        var fileValues: PhotoFileMetadata?
    }

    /// The library's file-facing representation of a photo: rating, orientation
    /// and the *resolved keyword paths* — exactly what import stores and what
    /// `dc:subject` carries.
    private func syncJobs() -> [SyncJob] {
        guard let snapshot else { return [] }
        return snapshot.photos.compactMap { photo in
            photo.id.map { id in
                SyncJob(
                    photoId: id,
                    path: photo.path,
                    libraryValues: PhotoFileMetadata(
                        rating: photo.rating,
                        orientation: photo.orientation,
                        keywords: queryFacts(forPhotoId: id).keywordPaths.sorted()
                    )
                )
            }
        }
    }

    // MARK: Save Metadata into Files

    /// Library → files. Files already in sync are skipped (cheap re-runs);
    /// unreadable files are skipped AND reported (Q27) — never written blind.
    func saveMetadataToFiles() async {
        guard !isSyncing, snapshot != nil else { return }
        isSyncing = true
        defer { isSyncing = false }

        let jobs = syncJobs()
        var written = 0
        var failures: [String] = []
        var unreadable: [String] = []

        for outcome in await Self.performSave(jobs) {
            switch outcome {
            case .written: written += 1
            case .inSync: break
            case .unreadable(let path): unreadable.append(path)
            case .failed(let path): failures.append(path)
            }
        }

        let inSync = jobs.count - written - unreadable.count - failures.count
        var message = "Saved metadata into \(written) file\(written == 1 ? "" : "s")."
        if inSync > 0 { message += " \(inSync) already in sync." }
        message += fileList("Failed to write", failures)
        message += fileList("Skipped unreadable", unreadable)
        infoMessage = message
    }

    // MARK: Load Metadata from Files

    /// Files → library. The file wins for every readable file that differs;
    /// unreadable files are skipped (they'd otherwise read as empty and wipe
    /// library data — the spec §6.1 quirk). The whole load is one undo step.
    func loadMetadataFromFiles() async {
        guard !isSyncing, snapshot != nil else { return }
        isSyncing = true
        defer { isSyncing = false }

        let jobs = syncJobs()
        let reads = await Self.readFiles(for: jobs)
        var changes: [(photoId: Int64, values: PhotoFileMetadata)] = []
        var unreadable: [String] = []
        for result in reads {
            guard let fileValues = result.fileValues else {
                unreadable.append(result.job.path)
                continue
            }
            if MetadataSync.differs(result.job.libraryValues, fileValues) {
                changes.append((result.job.photoId, fileValues))
            }
        }

        applyMetadataValues(changes, actionName: "Load Metadata")

        var message = "Loaded metadata from \(changes.count) file\(changes.count == 1 ? "" : "s")."
        let inSync = jobs.count - changes.count - unreadable.count
        if inSync > 0 { message += " \(inSync) already in sync." }
        message += fileList("Skipped unreadable", unreadable)
        infoMessage = message
    }

    /// Applies per-photo (rating, orientation, keyword set) values in one write
    /// transaction and registers the inverse as a single undo step. Keywords
    /// resolve through find-or-create node chains — the vocabulary only ever
    /// grows, never shrinks (fixes D2).
    func applyMetadataValues(
        _ changes: [(photoId: Int64, values: PhotoFileMetadata)], actionName: String
    ) {
        guard !changes.isEmpty, let snapshot else { return }

        // Inverse state before touching anything — same shape, same applier.
        let before: [(photoId: Int64, values: PhotoFileMetadata)] = changes.compactMap { change in
            photo(withId: change.photoId).map { record in
                (change.photoId, PhotoFileMetadata(
                    rating: record.rating,
                    orientation: record.orientation,
                    keywords: queryFacts(forPhotoId: change.photoId).keywordPaths.sorted()
                ))
            }
        }

        struct TxResult {
            var keywordRecords: [KeywordRecord]
            var idsByPhoto: [Int64: Set<Int64>]
        }
        guard let result: TxResult = writeSync({ db in
            var idsByPhoto: [Int64: Set<Int64>] = [:]
            for change in changes {
                try PhotoDAO.setRatings([(change.photoId, change.values.rating)], in: db)
                try PhotoDAO.setOrientations([(change.photoId, change.values.orientation)], in: db)
                var keywordIds: Set<Int64> = []
                for keywordPath in change.values.keywords {
                    let components = keywordPath.components(separatedBy: KeywordTree.separator)
                    keywordIds.insert(try KeywordDAO.ensurePath(components, groupId: nil, in: db))
                }
                try PhotoDAO.setKeywords(Array(keywordIds), forPhotoId: change.photoId, in: db)
                idsByPhoto[change.photoId] = keywordIds
            }
            return TxResult(keywordRecords: try KeywordDAO.fetchAll(db), idsByPhoto: idsByPhoto)
        }) else { return }

        _ = mutatePhotos(ids: changes.map(\.photoId)) { photo in
            guard let change = changes.first(where: { $0.photoId == photo.id }) else { return }
            photo.rating = change.values.rating
            photo.orientation = change.values.orientation
        }
        mutateSnapshot { snapshot in
            snapshot.keywordTree = KeywordTree(records: result.keywordRecords)
            for (photoId, keywordIds) in result.idsByPhoto {
                snapshot.keywordIdsByPhoto[photoId] = keywordIds
            }
        }
        invalidateFacts(forPhotoIds: changes.map(\.photoId))
        registerUndo(actionName) { $0.applyMetadataValues(before, actionName: actionName) }
        emitCatalogEvent(.photosUpdated(changes.map(\.photoId)))
    }

    // MARK: Helpers

    private enum SaveOutcome: Sendable {
        case written, inSync
        case unreadable(String)
        case failed(String)
    }

    /// Read → compare → write per photo, bounded to 8 concurrent jobs (writes
    /// are heavier than the import-time reads).
    nonisolated private static func performSave(_ jobs: [SyncJob]) async -> [SaveOutcome] {
        await withTaskGroup(of: SaveOutcome.self, returning: [SaveOutcome].self) { group in
            var results: [SaveOutcome] = []
            results.reserveCapacity(jobs.count)
            var iterator = jobs.makeIterator()
            func addNext() {
                guard let job = iterator.next() else { return }
                group.addTask {
                    let url = URL(fileURLWithPath: job.path)
                    guard let fileValues = MetadataReader.readIfReadable(from: url) else {
                        return .unreadable(job.path)
                    }
                    guard MetadataSync.differs(job.libraryValues, fileValues) else {
                        return .inSync
                    }
                    do {
                        try MetadataWriter.write(
                            rating: job.libraryValues.rating,
                            orientation: job.libraryValues.orientation,
                            keywords: job.libraryValues.keywords,
                            to: url
                        )
                        return .written
                    } catch {
                        return .failed(job.path)
                    }
                }
            }
            for _ in 0..<8 { addNext() }
            for await outcome in group {
                results.append(outcome)
                addNext()
            }
            return results
        }
    }

    /// Bounded concurrent file reads (12, matching import).
    nonisolated private static func readFiles(for jobs: [SyncJob]) async -> [FileReadResult] {
        await withTaskGroup(of: FileReadResult.self, returning: [FileReadResult].self) { group in
            var results: [FileReadResult] = []
            results.reserveCapacity(jobs.count)
            var iterator = jobs.makeIterator()
            func addNext() {
                guard let job = iterator.next() else { return }
                group.addTask {
                    FileReadResult(
                        job: job,
                        fileValues: MetadataReader.readIfReadable(
                            from: URL(fileURLWithPath: job.path)
                        )
                    )
                }
            }
            for _ in 0..<12 { addNext() }
            for await result in group {
                results.append(result)
                addNext()
            }
            return results
        }
    }

    /// Q27: skipped/failed files are listed, capped so the alert stays readable.
    private func fileList(_ label: String, _ paths: [String]) -> String {
        guard !paths.isEmpty else { return "" }
        let names = paths.prefix(8).map { "• " + ($0 as NSString).lastPathComponent }
        let more = paths.count > 8 ? "\n… and \(paths.count - 8) more" : ""
        return "\n\n\(label) \(paths.count) file\(paths.count == 1 ? "" : "s"):\n"
            + names.joined(separator: "\n") + more
    }
}
