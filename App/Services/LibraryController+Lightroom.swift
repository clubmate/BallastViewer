import AppKit
import BallastCore
import GRDB
import UniformTypeIdentifiers

/// "Import Metadata from Lightroom…": merges ratings and keywords from a
/// Lightroom Classic catalog (an `.lrcat` is itself SQLite) into photos that
/// are ALREADY in the open library — it never adds photos. Matching is by
/// path, with a unique-filename fallback for files that moved folders since
/// Lightroom last saw them. The merged values reach the image files through
/// the regular debounced write-through; pixels stay untouched as always.
extension LibraryController {
    func presentImportLightroomPanel() {
        guard libraryURL != nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Metadata from Lightroom"
        panel.message = "Choose a Lightroom Classic catalog (.lrcat). Ratings and keywords are merged"
            + " into photos already in this library. Quit Lightroom first so the catalog is fully saved."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let lrcat = UTType(filenameExtension: "lrcat") {
            panel.allowedContentTypes = [lrcat]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importLightroomMetadata(from: url) }
    }

    func importLightroomMetadata(from url: URL) async {
        guard let pipeline = writePipeline, snapshot != nil else { return }
        guard !isBusy else {
            errorMessage = Self.busyMessage
            return
        }
        // Same modal shield as the other bulk transactions: a rating pressed
        // while the merge transaction runs would race the snapshot reload.
        let wasBulkUpdating = isBulkUpdating
        isBulkUpdating = true
        defer { isBulkUpdating = wasBulkUpdating }

        let photos = (snapshot?.photos ?? []).compactMap { photo in
            photo.id.map { LightroomLibraryPhoto(id: $0, path: photo.path) }
        }
        // Catalog read + matching are disk I/O over a potentially huge file —
        // off the MainActor, like every other import read.
        let matchResult: Result<LightroomMatchResult, any Error> =
            await Task.detached(priority: .userInitiated) {
                do {
                    let entries = try Self.readLightroomCatalog(at: url)
                    return .success(LightroomMatcher.match(entries: entries, photos: photos))
                } catch {
                    return .failure(error)
                }
            }.value

        switch matchResult {
        case .failure(let error):
            errorMessage = "Could not read “\(url.lastPathComponent)”.\n\(error.localizedDescription)"
        case .success(let matched):
            do {
                let matches = matched.matches
                let summary = try await pipeline.submitAndWait { db in
                    try LightroomImportDAO.merge(matches, in: db)
                }
                if !summary.changedPhotoIds.isEmpty {
                    await refreshSnapshot()
                    // The merge transaction already set the dirty flags; this
                    // hands the photos to the debounced file write-through.
                    markNeedsFileWrite(summary.changedPhotoIds)
                }
                infoMessage = Self.lightroomSummary(matched: matched, summary: summary)
            } catch {
                errorMessage = "Lightroom import failed.\n\(error.localizedDescription)"
            }
        }
    }

    /// Reads the catalog from a private temp copy: Lightroom may hold locks on
    /// the live file, and SQLite may need to recover a WAL sidecar — neither
    /// is allowed to happen against the user's original. The sandbox grants
    /// the selected `.lrcat` itself; the `-wal`/`-shm` siblings are copied
    /// best-effort (without them the catalog reads as of Lightroom's last
    /// checkpoint, which quitting Lightroom performs anyway).
    nonisolated private static func readLightroomCatalog(at url: URL) throws -> [LightroomPhotoEntry] {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("lrcat-import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }
        let copy = tempDir.appendingPathComponent(url.lastPathComponent)
        try fileManager.copyItem(at: url, to: copy)
        for suffix in ["-wal", "-shm"] where fileManager.fileExists(atPath: url.path + suffix) {
            try? fileManager.copyItem(
                at: URL(fileURLWithPath: url.path + suffix),
                to: URL(fileURLWithPath: copy.path + suffix)
            )
        }
        return try LightroomCatalogReader.read(at: copy)
    }

    private static func lightroomSummary(
        matched: LightroomMatchResult, summary: LightroomMergeSummary
    ) -> String {
        func count(_ n: Int, _ noun: String) -> String {
            "\(n) \(noun)\(n == 1 ? "" : "s")"
        }
        var message: String
        if matched.matches.isEmpty {
            message = "No photos from the Lightroom catalog were found in this library."
        } else {
            message = "Matched \(count(matched.matches.count, "photo"))"
                + " (\(matched.pathMatches) by path, \(matched.filenameMatches) by filename)."
            if summary.changedPhotoIds.isEmpty {
                message += " Everything was already up to date."
            } else {
                message += " Applied \(count(summary.ratingsApplied, "rating")) and"
                    + " \(count(summary.assignmentsAdded, "keyword assignment"))"
                if summary.keywordsCreated > 0 {
                    message += " (\(count(summary.keywordsCreated, "new keyword")))"
                }
                message += "."
            }
        }
        if matched.unmatched > 0 {
            message += " \(count(matched.unmatched, "catalog photo")) not in this library."
        }
        if matched.ambiguous > 0 {
            message += " \(count(matched.ambiguous, "entry")) skipped as ambiguous"
                + " (same filename appears more than once)."
        }
        return message
    }
}
