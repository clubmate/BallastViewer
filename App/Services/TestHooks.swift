import AppKit
import BallastCore

/// Headless lifecycle checks, driven by environment variables so acceptance
/// criteria can be verified from the CLI (`FileManager.temporaryDirectory`
/// holds the test libraries — since U42 that is the user temp dir, no longer
/// the sandbox container). Debug builds only; inert unless BV_TEST is set.
///
/// Hooks: BV_TEST_CREATE=<name> · BV_TEST_OPEN=<name> · BV_TEST_IMPORT=<abs path>
/// (twice with BV_TEST_RESCAN=1) · BV_TEST_NONRECURSIVE=1 · BV_TEST_REMOVE=<abs path>
/// · BV_TEST_LRCAT=<abs path> (U30 Lightroom metadata import, bypassing the panel)
/// · BV_TEST_CULL=1 (step-6 acceptance flow) · BV_TEST_KEYWORDS=1 (step-8
/// acceptance flow) · BV_TEST_MERGE=1 (U40 rename-collision merge) ·
/// BV_TEST_BULKWRITE=1 (U46 auto bulk-run progress, needs ≥100 photos) ·
/// BV_TEST_AIREVIEW=1 (U48 pending-suggestion review flow, model-free, needs ≥4 photos) ·
/// BV_TEST_VLM=<n> (U49: saves the starter profile with test keywords, runs the
/// selected model over the first n visible photos, prints replies + counts) ·
/// BV_TEST_STEP9=1 (search + keyword-shortcut flow) ·
/// BV_TEST_SINGLE=1 (single view, no quit) ·
/// BV_TEST_ROTATE=<n> (rotate anchor n times, no quit) · BV_TEST_CLOSE=1
/// · BV_TEST_QUIT=1
enum TestHooks {
    /// True in headless hook runs. MainWindow skips presenting alerts then:
    /// sheet-close animations running inside the hooks' nested runloop spins
    /// crash AppKit's NSMoveHelper observer (flaky EXC_BAD_ACCESS). The hooks
    /// read `infoMessage`/`errorMessage` directly anyway.
    static var suppressesAlerts: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["BV_TEST"] != nil
        #else
        false
        #endif
    }

    @MainActor
    static func runIfRequested(
        _ controller: LibraryController,
        center: CenterViewModel,
        sidebar: SidebarViewModel,
        dispatcher: ActionDispatcher,
        keyMap: KeyMapStore,
        midiMap: MidiMapStore,
        models: VLMModelStore,
        runner: AutoTagRunner
    ) async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["BV_TEST"] != nil else { return }
        // Line-buffered stdout is block-buffered when piped; hook output must
        // arrive even if a later step hangs.
        setbuf(stdout, nil)

        if let name = env["BV_TEST_CREATE"] {
            let url = testURL(named: name)
            try? FileManager.default.removeItem(at: url)
            await controller.createLibrary(at: url)
        }
        if let name = env["BV_TEST_OPEN"] {
            await controller.openLibrary(at: testURL(named: name))
        }
        if let path = env["BV_TEST_IMPORT"] {
            let folderURL = URL(fileURLWithPath: path, isDirectory: true)
            let recursive = env["BV_TEST_NONRECURSIVE"] == nil
            await controller.importFolders([folderURL], recursive: recursive)
            printImportState(controller, label: "import")
            if env["BV_TEST_RESCAN"] != nil {
                await controller.importFolders([folderURL], recursive: recursive)
                printImportState(controller, label: "rescan")
            }
        }
        // U30: Lightroom metadata import without the open panel (the fixture
        // .lrcat lives in the container's temp dir, readable in the sandbox).
        if let path = env["BV_TEST_LRCAT"] {
            await controller.importLightroomMetadata(from: URL(fileURLWithPath: path))
            print(
                "BVLR info=\(quoted(controller.infoMessage))",
                "error=\(quoted(controller.errorMessage))",
                "bulkRun=\(controller.fileWriteThrough?.isBulkRun == true)",
                "pending=\(controller.fileWriteThrough?.pendingCount ?? -1)"
            )
        }
        if let path = env["BV_TEST_REMOVE"] {
            if let folder = controller.snapshot?.folders.first(where: { $0.path == path }) {
                await controller.removeFolder(folder)
            } else {
                controller.errorMessage = "BV_TEST_REMOVE: no folder registered at \(path)"
            }
            printImportState(controller, label: "remove")
        }
        if env["BV_TEST_CULL"] != nil {
            await runCullingChecks(controller, center: center, sidebar: sidebar, dispatcher: dispatcher)
        }
        if env["BV_TEST_KEYWORDS"] != nil {
            await runKeywordChecks(controller, center: center, sidebar: sidebar)
        }
        if env["BV_TEST_MERGE"] != nil {
            runMergeChecks(controller, center: center)
        }
        if env["BV_TEST_CHILDCOLL"] != nil {
            runChildCollectionChecks(controller, center: center, sidebar: sidebar)
        }
        if env["BV_TEST_BULKWRITE"] != nil {
            runBulkWriteChecks(controller, center: center)
        }
        if env["BV_TEST_AIREVIEW"] != nil {
            await runAIReviewChecks(controller, center: center, sidebar: sidebar)
        }
        if let count = env["BV_TEST_VLM"].flatMap({ Int($0) }) {
            await runVLMChecks(controller, models: models, runner: runner, count: count)
        }
        if let path = env["BV_TEST_QTN"] {
            runQuarantineProbe(zipAt: path)
        }
        if env["BV_TEST_STEP9"] != nil {
            runStep9Checks(controller, center: center, dispatcher: dispatcher, keyMap: keyMap)
        }
        if env["BV_TEST_STEP10"] != nil {
            await runStep10Checks(controller, center: center, dispatcher: dispatcher)
        }
        // U14: import into a CLOSED library and read its folders without ever
        // opening it into the UI.
        if let name = env["BV_TEST_MANAGE"], let path = env["BV_TEST_MANAGE_FOLDER"] {
            let target = testURL(named: name)
            let before = await controller.folders(inLibraryAt: target).count
            await controller.importFolders(
                [URL(fileURLWithPath: path, isDirectory: true)], recursive: true, into: target
            )
            let after = await controller.folders(inLibraryAt: target)
            print(
                "BVMANAGE target=\(target.lastPathComponent)",
                "foldersBefore=\(before) after=\(after.count)",
                "stillOpen=\(controller.libraryURL?.lastPathComponent ?? "none")",
                "info=\(quoted(controller.infoMessage))"
            )
        }
        // WAL crash test: rate photos in a tight loop until killed from outside.
        if env["BV_TEST_CHURN"] != nil {
            await runChurn(controller)
        }
        // MIDI end-to-end: seed bindings, then report state changes for a while
        // so an external virtual controller (scripts) can drive the app.
        if env["BV_TEST_MIDI"] != nil {
            await runMidiChecks(controller, center: center, midiMap: midiMap)
        }
        // Visual check: jump into single view on the second photo (no quit).
        if env["BV_TEST_SINGLE"] != nil {
            dispatcher.dispatch(.app(.nextPhoto))
            dispatcher.dispatch(.app(.nextPhoto))
            dispatcher.dispatch(.app(.viewSingle))
            printCullState(controller, center, label: "single")
        }
        // Visual check: rotate the anchor N times (Q5 transform-sign check).
        if let turns = env["BV_TEST_ROTATE"].flatMap(Int.init) {
            dispatcher.dispatch(.app(.nextPhoto))
            for _ in 0..<turns { dispatcher.dispatch(.app(.rotate)) }
            printCullState(controller, center, label: "rotate")
        }

        print(
            "BVTEST opened=\(controller.libraryURL?.lastPathComponent ?? "none")",
            "known=\(controller.knownLibraries.count)",
            "photos=\(controller.snapshot?.photos.count.description ?? "-")",
            "error=\(quoted(controller.errorMessage))"
        )

        if env["BV_TEST_CLOSE"] != nil {
            controller.closeLibrary()
            print("BVTEST closed opened=\(controller.libraryURL?.lastPathComponent ?? "none")")
        }
        if env["BV_TEST_QUIT"] != nil {
            exit(0)
        }
        #endif
    }

    #if DEBUG
    /// Step-6/7 acceptance flow, headless: inside a real "unrated" smart
    /// collection, rating the anchor advances to the next unrated photo (Q1) —
    /// never back to the top; rotate cycles the stored orientation (Q5);
    /// ratingUp is reachable (C5); star badges update via delta; everything
    /// (including the sidebar selection) persists across a close/reopen.
    @MainActor
    private static func runCullingChecks(
        _ controller: LibraryController,
        center: CenterViewModel,
        sidebar: SidebarViewModel,
        dispatcher: ActionDispatcher
    ) async {
        controller.createSmartGroup(named: "CULLING")
        guard let groupId = controller.snapshot?.smartGroups.last?.id,
              let collectionId = controller.createCollection(named: "UNRATED", inGroup: groupId),
              var unrated = controller.snapshot?.collections.first(where: { $0.id == collectionId })
        else {
            print("BVCULL error=could-not-create-collection")
            return
        }
        unrated.matchAll = true
        controller.saveCollection(unrated, rules: [("rating", "equals", "0")])
        center.selectSidebarItem(.collection(collectionId))
        print("BVCULL selectedCollection anchorIsFirst=\(center.selection.anchorId == center.visiblePhotos.first?.id)")
        // Move into the middle of the list so "advance" is distinguishable
        // from "jump to top".
        dispatcher.dispatch(.app(.nextPhoto))
        dispatcher.dispatch(.app(.nextPhoto))
        dispatcher.dispatch(.app(.nextPhoto))
        printCullState(controller, center, label: "start")

        let expectedNext = center.anchorPosition.flatMap { position in
            center.visiblePhotos.indices.contains(position + 1)
                ? center.visiblePhotos[position + 1].id : nil
        }
        dispatcher.dispatch(.app(.rate3))
        let advanced = center.selection.anchorId == expectedNext
        printCullState(controller, center, label: "rated3 advancedToNeighbour=\(advanced)")
        print(
            "BVQUERY counts all=\(sidebar.counts.allPhotos)",
            "ratings=\(sidebar.counts.ratings)",
            "unratedCollection=\(sidebar.counts.collections[collectionId].map(String.init) ?? "-")"
        )

        dispatcher.dispatch(.app(.ratingUp))
        printCullState(controller, center, label: "ratingUp")

        dispatcher.dispatch(.app(.rotate))
        dispatcher.dispatch(.app(.rotate))
        printCullState(controller, center, label: "rotatedTwice")

        // Async write-through, then reopen from disk to prove durability.
        try? await Task.sleep(for: .seconds(1))
        if let url = controller.libraryURL {
            controller.closeLibrary()
            await controller.openLibrary(at: url)
        }
        let photos = controller.snapshot?.photos ?? []
        print(
            "BVCULL persisted rated=\(photos.filter { $0.rating > 0 }.count)",
            "rotated=\(photos.filter { $0.orientation != 1 }.count)",
            "ratings=\(photos.filter { $0.rating > 0 }.map(\.rating).sorted())"
        )
        print(
            "BVQUERY restored item=\(center.activeItem.encoded)",
            "visible=\(center.visiblePhotos.count)",
            "collections=\(controller.snapshot?.collections.count ?? -1)"
        )

        // Collection-switch acceptance: switching always selects the first photo.
        center.selectSidebarItem(.rating(3))
        print(
            "BVQUERY switchRating3 visible=\(center.visiblePhotos.count)",
            "anchorIsFirst=\(center.selection.anchorId == center.visiblePhotos.first?.id)"
        )
        center.selectSidebarItem(.allPhotos)
        print(
            "BVQUERY switchAll visible=\(center.visiblePhotos.count)",
            "anchorIsFirst=\(center.selection.anchorId == center.visiblePhotos.first?.id)"
        )
    }

    /// Step-8 acceptance flow, headless: typing `ANNA` assigns `PEOPLE > ANNA`
    /// when the node exists (Q16); chips are ordered group-then-alpha with
    /// ungrouped grey last (Q18) and show the selection's intersection (Q14);
    /// renaming a node updates every chip path instantly (C4); assignments
    /// persist across a close/reopen.
    @MainActor
    private static func runKeywordChecks(
        _ controller: LibraryController,
        center: CenterViewModel,
        sidebar: SidebarViewModel
    ) async {
        func chips(for photoIds: [Int64]) -> [KeywordChip] {
            guard let snapshot = controller.snapshot else { return [] }
            return KeywordChipBuilder.chips(
                forKeywordIds: KeywordChipBuilder.commonKeywordIds(
                    photoIds: photoIds, keywordIdsByPhoto: snapshot.keywordIdsByPhoto
                ),
                tree: snapshot.keywordTree,
                groups: snapshot.keywordGroups
            )
        }
        func describe(_ chips: [KeywordChip]) -> String {
            chips.map { "\($0.path)[\($0.colorHex ?? "grey")]" }.joined(separator: ", ")
        }

        // Vocabulary: PEOPLE group gets PEOPLE > ANNA.
        guard let peopleGroupId = controller.snapshot?.keywordGroups
            .first(where: { $0.name == "PEOPLE" })?.id,
            let peopleId = controller.createKeyword(baseName: "PEOPLE", parentId: nil, groupId: peopleGroupId),
            let annaId = controller.createKeyword(baseName: "ANNA", parentId: peopleId, groupId: nil)
        else {
            print("BVKEY error=could-not-create-vocabulary")
            return
        }

        let photoIds = center.visiblePhotos.prefix(3).map(\.id)
        guard photoIds.count == 3 else {
            print("BVKEY error=needs-three-photos")
            return
        }

        // Q16: typing the bare name resolves to the full path.
        controller.assignKeyword(text: "anna", toPhotoIds: [photoIds[0], photoIds[1]])
        // Ad-hoc keyword (no vocabulary match) → grey chip, sorted last (Q18).
        controller.assignKeyword(text: "sunset", toPhotoIds: [photoIds[0], photoIds[1]])
        print("BVKEY assigned chips=\(describe(chips(for: [photoIds[0]])))")

        // Q14: the third photo has nothing — intersection over all three is empty.
        print(
            "BVKEY intersection pair=\(chips(for: [photoIds[0], photoIds[1]]).count)",
            "triple=\(chips(for: photoIds).count)"
        )

        // C4: renaming the node rewrites every derived chip path instantly.
        controller.renameKeyword(annaId, to: "ANNA-LENA")
        print("BVKEY renamed chips=\(describe(chips(for: [photoIds[0]])))")

        // Toggle removes from all carriers (spec §8.4).
        controller.toggleKeyword(text: "SUNSET", forPhotoIds: [photoIds[0], photoIds[1]])
        print("BVKEY toggledOff chips=\(describe(chips(for: [photoIds[0]])))")

        // Durability: reopen from disk.
        try? await Task.sleep(for: .seconds(1))
        if let url = controller.libraryURL {
            controller.closeLibrary()
            await controller.openLibrary(at: url)
        }
        let restoredFirst = controller.snapshot?.photos.compactMap(\.id)
            .first(where: { controller.snapshot?.keywordIdsByPhoto[$0]?.isEmpty == false })
        print(
            "BVKEY persisted assignments=\(controller.snapshot?.keywordIdsByPhoto.values.map(\.count).reduce(0, +) ?? -1)",
            "keywords=\(controller.snapshot?.keywordTree.count ?? -1)",
            "firstCarrierChips=\(describe(restoredFirst.map { chips(for: [$0]) } ?? []))"
        )
    }

    /// Updater diagnosis: replays the install pipeline (FileHandle byte copy
    /// like the streaming download → `ditto -xk`) inside the sandbox and
    /// reports the quarantine state of every stage, then tries to strip the
    /// attribute the way a fix would — so we KNOW instead of guessing.
    private static func runQuarantineProbe(zipAt sourcePath: String) {
        func qtn(_ path: String) -> String {
            var buffer = [CChar](repeating: 0, count: 256)
            let n = getxattr(path, "com.apple.quarantine", &buffer, buffer.count, 0, 0)
            guard n > 0 else { return "none" }
            return String(decoding: buffer.prefix(Int(n)).map(UInt8.init(bitPattern:)), as: UTF8.self)
        }
        do {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("qtnprobe", isDirectory: true)
            try? FileManager.default.removeItem(at: work)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            // Byte copy through FileHandle — the same write path the
            // streaming download uses (FileManager.copyItem would copy the
            // SOURCE's xattrs and hide what the sandbox adds on its own).
            let zip = work.appendingPathComponent("update.zip")
            let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
            FileManager.default.createFile(atPath: zip.path, contents: nil)
            let handle = try FileHandle(forWritingTo: zip)
            try handle.write(contentsOf: data)
            try handle.close()
            print("BVQTN zip=\(qtn(zip.path))")

            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zip.path, work.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard let app = try FileManager.default
                .contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
            else {
                print("BVQTN error=no-app-in-zip")
                return
            }
            let executable = app.appendingPathComponent("Contents/MacOS/BallastViewer")
            print("BVQTN app=\(qtn(app.path)) exe=\(qtn(executable.path))")

            // The fix candidate: strip recursively via removexattr.
            var failures = 0
            var removed = 0
            let paths = [app.path] + (FileManager.default
                .enumerator(at: app, includingPropertiesForKeys: nil)?
                .compactMap { ($0 as? URL)?.path } ?? [])
            for path in paths where qtn(path) != "none" {
                if removexattr(path, "com.apple.quarantine", 0) == 0 {
                    removed += 1
                } else {
                    failures += 1
                }
            }
            print(
                "BVQTN strip removed=\(removed) failed=\(failures)",
                "appAfter=\(qtn(app.path)) exeAfter=\(qtn(executable.path))"
            )
        } catch {
            print("BVQTN error=\(error.localizedDescription)")
        }
    }

    /// U40 acceptance, headless: renaming "_STRASSE" to "STRASSE" next to an
    /// existing sibling is flagged as a merge candidate, and the confirmed
    /// merge folds it in — assignments union, source gone, carriers re-derived.
    @MainActor
    private static func runMergeChecks(_ controller: LibraryController, center: CenterViewModel) {
        guard let metaId = controller.createKeyword(baseName: "META", parentId: nil, groupId: nil),
              let strasseId = controller.createKeyword(baseName: "STRASSE", parentId: metaId, groupId: nil),
              let sourceId = controller.createKeyword(baseName: "_STRASSE", parentId: metaId, groupId: nil)
        else {
            print("BVMERGE error=could-not-create-vocabulary")
            return
        }
        let photoIds = center.visiblePhotos.prefix(2).map(\.id)
        guard photoIds.count == 2 else {
            print("BVMERGE error=needs-two-photos")
            return
        }
        controller.assignKeyword(id: strasseId, toPhotoIds: [photoIds[0]])
        controller.assignKeyword(id: sourceId, toPhotoIds: [photoIds[1]])

        // "setup" leaves the collision in place for a manual UI pass.
        if ProcessInfo.processInfo.environment["BV_TEST_MERGE"] == "setup" {
            print("BVMERGE setup done")
            return
        }

        let candidate = controller.keywordRenameMergeCandidate(sourceId, newName: "strasse")
        // A non-colliding rename must NOT be flagged.
        let noCandidate = controller.keywordRenameMergeCandidate(sourceId, newName: "GASSE")
        print("BVMERGE candidate=\(candidate == strasseId) noCandidate=\(noCandidate == nil)")

        controller.mergeKeyword(sourceId, into: strasseId)
        let tree = controller.snapshot?.keywordTree
        let survivors = tree?.children(of: metaId).compactMap { tree?.node($0)?.name } ?? []
        let carriers = photoIds.filter {
            controller.snapshot?.keywordIdsByPhoto[$0]?.contains(strasseId) == true
        }
        print(
            "BVMERGE merged children=\(survivors.joined(separator: ","))",
            "sourceGone=\(tree?.node(sourceId) == nil)",
            "bothCarry=\(carriers.count == 2)"
        )
    }

    /// U46 acceptance, headless: a keyword change touching ≥ 100 photos turns
    /// the write-through into a visible bulk run WITHOUT anyone declaring
    /// one; a 2-photo change does not. Prints the state right after the
    /// mutation (during the debounce window, before any file is written).
    @MainActor
    private static func runBulkWriteChecks(_ controller: LibraryController, center: CenterViewModel) {
        guard let writer = controller.fileWriteThrough,
              let smallId = controller.createKeyword(baseName: "BULK SMALL", parentId: nil, groupId: nil),
              let bigId = controller.createKeyword(baseName: "BULK BIG", parentId: nil, groupId: nil)
        else {
            print("BVBULK error=setup")
            return
        }
        let all = center.visiblePhotos.map(\.id)
        guard all.count >= MetadataWriteThrough.bulkRunThreshold else {
            print("BVBULK error=needs-\(MetadataWriteThrough.bulkRunThreshold)-photos have=\(all.count)")
            return
        }
        controller.assignKeyword(id: smallId, toPhotoIds: Array(all.prefix(2)))
        print("BVBULK small bulkRun=\(writer.isBulkRun) pending=\(writer.pendingCount)")
        controller.assignKeyword(id: bigId, toPhotoIds: all)
        print("BVBULK assign bulkRun=\(writer.isBulkRun) pending=\(writer.pendingCount) total=\(writer.runTotal)")
        // A rename of a keyword carried by every photo re-flags them all.
        controller.renameKeyword(bigId, to: "BULK RENAMED")
        print("BVBULK rename bulkRun=\(writer.isBulkRun) pending=\(writer.pendingCount) total=\(writer.runTotal)")
    }

    /// U48 Stage 2+3 acceptance, headless and MODEL-FREE (seeds suggestions
    /// through `applySuggestions` exactly like the runner would): the sidebar
    /// review count, the .pendingReview filter, accept (→ confirmed +
    /// needsFileWrite), reject (→ tombstone, NO file write), tombstone
    /// suppression on a re-run, and manual assign as implicit accept.
    @MainActor
    private static func runAIReviewChecks(
        _ controller: LibraryController, center: CenterViewModel, sidebar: SidebarViewModel
    ) async {
        guard let keywordId = controller.createKeyword(
            baseName: "AI REVIEW", parentId: nil, groupId: nil)
        else {
            print("BVAIREVIEW error=setup")
            return
        }
        let all = center.visiblePhotos.map(\.id)
        guard all.count >= 4 else {
            print("BVAIREVIEW error=needs-4-photos have=\(all.count)")
            return
        }
        let pairs = all.prefix(3).map { PhotoKeywordPair(photoId: $0, keywordId: keywordId) }
        let libraryUUID = controller.snapshot?.meta.libraryUUID ?? ""
        controller.applySuggestions(Array(pairs), libraryUUID: libraryUUID)
        print("BVAIREVIEW seeded reviewCount=\(sidebar.pendingReviewCount)")

        // Review fix 2026-09-02: Remove Folder + Undo must bring the pending
        // suggestions back as PENDING (never as confirmed, file-facing
        // keywords) and keep the rejection memory. Ids are restored verbatim,
        // so the flow below continues on the same photos.
        // Photo 4: suggest → reject (tombstone) → seed again directly, so the
        // folder carries a pending row AND a tombstone for the same pair.
        let fourth = [PhotoKeywordPair(photoId: all[3], keywordId: keywordId)]
        controller.applySuggestions(fourth, libraryUUID: libraryUUID)
        controller.rejectPendingKeyword(id: keywordId, forPhotoIds: [all[3]])
        controller.applySuggestions(fourth, libraryUUID: libraryUUID)
        if let folder = controller.snapshot?.folders.first {
            let photoCount = controller.snapshot?.photos.count ?? 0
            await controller.removeFolder(folder)
            let removedCount = controller.snapshot?.photos.count ?? -1
            controller.undoManager?.undoNestedGroup()
            var waited = 0
            while (controller.snapshot?.photos.count ?? 0) < photoCount, waited < 200 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
            let pending = controller.snapshot?.pendingKeywordIdsByPhoto
                .reduce(0) { $0 + ($1.value.contains(keywordId) ? 1 : 0) } ?? -1
            let confirmed = controller.snapshot?.keywordIdsByPhoto
                .reduce(0) { $0 + ($1.value.contains(keywordId) ? 1 : 0) } ?? -1
            let tombstone = controller.fetchRejectedSuggestionPairs()
                .contains(PhotoKeywordPair(photoId: all[3], keywordId: keywordId))
            print(
                "BVAIREVIEW removeUndo removed=\(removedCount) restored=\(controller.snapshot?.photos.count ?? -1)",
                "pending=\(pending) confirmed=\(confirmed) tombstone=\(tombstone)",
                "reviewCount=\(sidebar.pendingReviewCount)"
            )
        }

        center.selectSidebarItem(.pendingReview)
        print("BVAIREVIEW queue visible=\(center.visiblePhotos.count) item=\(center.activeItem.encoded)")

        controller.acceptPendingKeyword(id: keywordId, forPhotoIds: [all[0]])
        print(
            "BVAIREVIEW accept",
            "confirmed=\(controller.snapshot?.keywordIdsByPhoto[all[0]]?.contains(keywordId) == true)",
            "needsWrite=\(controller.photo(withId: all[0])?.needsFileWrite == true)",
            "visible=\(center.visiblePhotos.count)",
            "reviewCount=\(sidebar.pendingReviewCount)"
        )

        controller.rejectPendingKeyword(id: keywordId, forPhotoIds: [all[1]])
        let tombstones = controller.fetchRejectedSuggestionPairs()
        print(
            "BVAIREVIEW reject",
            "tombstone=\(tombstones.contains(PhotoKeywordPair(photoId: all[1], keywordId: keywordId)))",
            "needsWrite=\(controller.photo(withId: all[1])?.needsFileWrite == true)",
            "visible=\(center.visiblePhotos.count)",
            "reviewCount=\(sidebar.pendingReviewCount)"
        )

        // A re-run offers the same pairs again; the runner's skip set (here:
        // the tombstones) plus the in-memory confirmed/pending checks must
        // let NOTHING back through.
        let retry = pairs.filter { !tombstones.contains($0) }
        controller.applySuggestions(retry, libraryUUID: libraryUUID)
        print(
            "BVAIREVIEW resuggest retried=\(retry.count)",
            "reviewCount=\(sidebar.pendingReviewCount)",
            "visible=\(center.visiblePhotos.count)"
        )

        // Typing the keyword on the last pending photo = implicit accept; the
        // queue empties and the review view runs dry.
        controller.assignKeyword(id: keywordId, toPhotoIds: [all[2]])
        print(
            "BVAIREVIEW implicitAccept",
            "confirmed=\(controller.snapshot?.keywordIdsByPhoto[all[2]]?.contains(keywordId) == true)",
            "pendingGone=\(controller.snapshot?.pendingKeywordIdsByPhoto[all[2]]?.contains(keywordId) != true)",
            "reviewCount=\(sidebar.pendingReviewCount)",
            "visible=\(center.visiblePhotos.count)"
        )

        // Emergency exit (2026-09-02): discard drops every pending pair with
        // NO tombstones, and undo brings them back.
        let tombstonesBefore = controller.fetchRejectedSuggestionPairs().count
        controller.discardPendingSuggestions(controller.allPendingSuggestionPairs)
        let afterDiscard = sidebar.pendingReviewCount
        let tombstonesAfter = controller.fetchRejectedSuggestionPairs().count
        controller.undoManager?.undoNestedGroup()
        print(
            "BVAIREVIEW discard reviewCount=\(afterDiscard) tombstonesUnchanged=\(tombstonesBefore == tombstonesAfter)",
            "undoReviewCount=\(sidebar.pendingReviewCount) visible=\(center.visiblePhotos.count)"
        )
    }

    /// U49 end-to-end, headless (needs the SELECTED model downloaded): saves
    /// the starter profile with the first three questions mapped to fresh
    /// test keywords, runs it over the first `count` visible photos and
    /// prints one line per photo with the keywords now pending on it.
    @MainActor
    private static func runVLMChecks(
        _ controller: LibraryController, models: VLMModelStore, runner: AutoTagRunner, count: Int
    ) async {
        // Never on the last-opened library: this hook creates keywords and
        // pending suggestions, so it insists on an explicit test library.
        guard ProcessInfo.processInfo.environment["BV_TEST_OPEN"] != nil
            || ProcessInfo.processInfo.environment["BV_TEST_CREATE"] != nil
        else {
            print("BVVLM error=needs-BV_TEST_OPEN (refusing to run on the last-opened library)")
            return
        }
        var waited = 0
        while controller.snapshot == nil, waited < 600 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        guard let snapshot = controller.snapshot else {
            print("BVVLM error=no-library")
            return
        }
        // The run reads the real defaults; put them back afterwards.
        let savedThinking = UserDefaults.standard.object(forKey: AISettingsView.thinkingKey)
        let savedFullRes = UserDefaults.standard.object(forKey: AISettingsView.fullResolutionKey)
        defer {
            UserDefaults.standard.set(savedThinking, forKey: AISettingsView.thinkingKey)
            UserDefaults.standard.set(savedFullRes, forKey: AISettingsView.fullResolutionKey)
        }
        if let override = ProcessInfo.processInfo.environment["BV_TEST_VLM_MODEL"] {
            models.selectedId = override
            models.refreshStates()
        }
        let env = ProcessInfo.processInfo.environment
        UserDefaults.standard.set(env["BV_TEST_VLM_THINK"] != nil, forKey: AISettingsView.thinkingKey)
        UserDefaults.standard.set(env["BV_TEST_VLM_FULLRES"] != nil, forKey: AISettingsView.fullResolutionKey)
        print("BVVLM model=\(models.selectedId) state=\(models.state(of: models.selectedId))")
        // Test keywords: VLM TEST > <question>/<answer> for the first three
        // questions (people, gender, age); the rest stay unmapped.
        var profile = AIProfile.starter()
        profile.name = "VLM TEST"
        for qIndex in 0 ..< min(3, profile.questions.count) {
            for aIndex in profile.questions[qIndex].answers.indices {
                let value = profile.questions[qIndex].answers[aIndex].value
                guard value != "none" else { continue }
                let name = "\(["PEOPLE", "GENDER", "AGE"][qIndex]) \(value.uppercased())"
                let id = controller.snapshot?.keywordTree.find(pathComponents: ["VLM TEST", name])
                    ?? controller.createKeyword(
                        baseName: name,
                        parentId: controller.snapshot?.keywordTree.find(pathComponents: ["VLM TEST"])
                            ?? controller.createKeyword(baseName: "VLM TEST", parentId: nil, groupId: nil),
                        groupId: nil
                    )
                profile.questions[qIndex].answers[aIndex].keywordId = id
            }
        }
        // Replace a previous test profile so reruns do not stack.
        if let stale = controller.snapshot?.aiProfiles.first(where: { $0.name == "VLM TEST" })?.id {
            controller.deleteAIProfile(stale)
        }
        guard let saved = controller.saveAIProfile(profile) else {
            print("BVVLM error=save-profile")
            return
        }
        print("BVVLM profile=\(saved.id ?? -1) questions=\(saved.questions.count) mapped=\(saved.keywordIds.count)")
        let photos = Array(snapshot.photos.prefix(count))
        let started = Date()
        runner.run(controller: controller, models: models, photos: photos, scopeName: "VLM TEST")
        while runner.isRunning {
            try? await Task.sleep(for: .milliseconds(200))
        }
        if case .failed(let message) = runner.phase {
            print("BVVLM error=run-failed message=\(message)")
            return
        }
        print("BVVLM summary=\(runner.summary ?? "-") seconds=\(Int(Date().timeIntervalSince(started)))")
        guard let tree = controller.snapshot?.keywordTree else { return }
        for photo in photos {
            guard let id = photo.id else { continue }
            let pending = (controller.snapshot?.pendingKeywordIdsByPhoto[id] ?? [])
                .map { tree.path(of: $0) }.sorted()
            print("BVVLM photo=\((photo.path as NSString).lastPathComponent) pending=\(pending.joined(separator: " | "))")
        }
    }

    /// U41 acceptance, headless: a child collection ANDs the parent's rules
    /// onto its own — counts and the active-collection filter follow the
    /// chain. Leaves the structure in place for a manual UI pass.
    @MainActor
    private static func runChildCollectionChecks(
        _ controller: LibraryController, center: CenterViewModel, sidebar: SidebarViewModel
    ) {
        // Idempotent-ish: a leftover CHAIN group from a previous run goes
        // first, so reruns don't stack duplicate groups.
        while let stale = controller.snapshot?.smartGroups.first(where: { $0.name == "CHAIN" })?.id {
            controller.deleteSmartGroup(stale)
        }
        controller.createSmartGroup(named: "CHAIN")
        guard let groupId = controller.snapshot?.smartGroups.last?.id else {
            print("BVCHILD error=no-group")
            return
        }
        guard let parentId = controller.createCollection(named: "STRASSE", inGroup: groupId),
              let parent = controller.snapshot?.collections.first(where: { $0.id == parentId })
        else {
            print("BVCHILD error=no-parent")
            return
        }
        controller.saveCollection(parent, rules: [("keyword", "contains", "STRASSE")])
        guard let childId = controller.createCollection(
                  named: "M1", inGroup: groupId, parentId: parentId
              ),
              let child = controller.snapshot?.collections.first(where: { $0.id == childId })
        else {
            print("BVCHILD error=no-child")
            return
        }
        controller.saveCollection(child, rules: [("filename", "contains", "m1")])
        // Third level + a leaf sibling, so the outline rendering (guide
        // lines, chevron alignment) is inspectable in the UI pass.
        _ = controller.createCollection(named: "ALL", inGroup: groupId, parentId: childId)
        _ = controller.createCollection(named: "M2", inGroup: groupId, parentId: parentId)
        center.selectSidebarItem(.collection(childId))
        print(
            "BVCHILD parentCount=\(sidebar.counts.collections[parentId] ?? -1)",
            "childCount=\(sidebar.counts.collections[childId] ?? -1)",
            "visibleInChild=\(center.visiblePhotos.count)",
            "descendants=\(controller.collectionDescendantCount(parentId))"
        )
    }

    /// Step-9 acceptance flow, headless: a keyword shortcut created for `anna`
    /// stores the canonical `keyword:PEOPLE > ANNA` binding (C7), dispatching
    /// it toggles the resolved keyword on the selection, and search filters by
    /// keyword AND filename (U5) on top of the active collection.
    @MainActor
    private static func runStep9Checks(
        _ controller: LibraryController,
        center: CenterViewModel,
        dispatcher: ActionDispatcher,
        keyMap: KeyMapStore
    ) {
        func anchorPaths() -> [String] {
            guard let snapshot = controller.snapshot,
                  let anchor = center.selection.anchorId else { return [] }
            return (snapshot.keywordIdsByPhoto[anchor] ?? [])
                .map { snapshot.keywordTree.path(of: $0) }
                .sorted()
        }

        guard let peopleId = controller.createKeyword(baseName: "PEOPLE", parentId: nil, groupId: nil),
              controller.createKeyword(baseName: "ANNA", parentId: peopleId, groupId: nil) != nil,
              let tree = controller.snapshot?.keywordTree
        else {
            print("BVS9 error=could-not-create-vocabulary")
            return
        }

        // C7: the binding stores the resolved path, not the literal text.
        let canonical = KeywordResolver.canonicalText("anna", tree: tree)
        if let canonical, let chord = KeyChord(key: "k") {
            keyMap.assign(chord, to: .keyword(canonical))
        }
        print("BVS9 binding=\(keyMap.map.bindings["k"] ?? "none")")

        // Dispatch toggles the resolved keyword on the anchor (on, then off).
        dispatcher.dispatch(.keyword("anna"))
        print("BVS9 toggledOn=\(anchorPaths())")
        dispatcher.dispatch(.keyword("anna"))
        print("BVS9 toggledOff=\(anchorPaths())")

        // Search: keyword hit, filename hit, miss — then cleared (U5 chip flow).
        dispatcher.dispatch(.keyword("anna"))
        let total = center.visiblePhotos.count
        center.searchText = "anna"
        center.applySearchNow()
        print("BVS9 searchKeyword visible=\(center.visiblePhotos.count) of=\(total)")
        let fragment = controller.snapshot?.photos.first
            .map { String($0.filename.prefix(4)) } ?? ""
        center.searchText = fragment
        center.applySearchNow()
        print("BVS9 searchFilename query=\(fragment) visible=\(center.visiblePhotos.count)")
        center.searchText = "zzz-no-match"
        center.applySearchNow()
        print("BVS9 searchMiss visible=\(center.visiblePhotos.count)")
        center.searchText = ""
        print("BVS9 searchCleared visible=\(center.visiblePhotos.count)")
    }

    /// Step-10 acceptance flow, headless. Undo groups close per runloop turn,
    /// so distinct steps are separated by short sleeps — mirroring real
    /// one-gesture-per-event usage.
    @MainActor
    private static func runStep10Checks(
        _ controller: LibraryController,
        center: CenterViewModel,
        dispatcher: ActionDispatcher
    ) async {
        func pause() async {
            spinRunLoop()
            try? await Task.sleep(for: .milliseconds(30))
        }
        // NSUndoManager's implicit per-event groups never close in a headless
        // run (no real events reach sendEvent), which would merge every
        // gesture into one giant group. With groupsByEvent off, the explicit
        // begin/end pair in LibraryController.registerUndo delimits each
        // gesture instead.
        controller.undoManager?.groupsByEvent = false
        func anchorState() -> String {
            guard let id = center.selection.anchorId, let record = controller.photo(withId: id),
                  let snapshot = controller.snapshot else { return "none" }
            let paths = snapshot.queryFacts(for: record).keywordPaths.sorted()
            return "anchor=\(id) rating=\(record.rating) orientation=\(record.orientation) keywords=\(paths)"
        }
        func dumpAll(_ label: String) {
            let rows = (controller.snapshot?.photos ?? []).map {
                "\($0.id ?? -1):\($0.rating)/\($0.orientation)"
            }
            print("BVS10 dump \(label) \(rows.joined(separator: " "))")
        }
        print("BVS10 undoManager=\(controller.undoManager != nil)")

        // Library state: rating 4, one rotation (1→6), PEOPLE > ANNA assigned.
        guard let peopleId = controller.createKeyword(baseName: "PEOPLE", parentId: nil, groupId: nil),
              controller.createKeyword(baseName: "ANNA", parentId: peopleId, groupId: nil) != nil
        else {
            print("BVS10 error=vocabulary")
            return
        }
        dispatcher.dispatch(.app(.rate4))
        await pause()
        dispatcher.dispatch(.app(.rotate))
        await pause()
        controller.toggleKeyword(text: "anna", forPhotoIds: [center.selection.anchorId!])
        await pause()
        print("BVS10 state \(anchorState())")
        dumpAll("after-setup")

        // Batch rating: three photos → one ⌘Z reverts all three (U8).
        let ids = center.visiblePhotos.prefix(3).map(\.id)
        center.selection.selectSingle(ids[0])
        for id in ids.dropFirst() { center.selection.toggle(id) }
        dispatcher.dispatch(.app(.rate5))
        await pause()
        func ratings() -> [Int] { ids.compactMap { controller.photo(withId: $0)?.rating } }
        print("BVS10 batch-rated ratings=\(ratings())")
        await pause()
        controller.undoManager?.undo()
        print("BVS10 batch-undone ratings=\(ratings())")
        await pause()

        // Keyword toggle undo.
        controller.toggleKeyword(text: "anna", forPhotoIds: Array(ids))
        await pause()
        await pause()
        controller.undoManager?.undo()
        let carriers = controller.snapshot?.keywordIdsByPhoto.values.filter { !$0.isEmpty }.count ?? -1
        print("BVS10 keyword-undone carriers=\(carriers)")
        await pause()

        // Folder removal undo restores photos and assignments.
        let countBefore = controller.snapshot?.photos.count ?? -1
        if let folder = controller.snapshot?.folders.first {
            await controller.removeFolder(folder)
            controller.infoMessage = nil
            print("BVS10 folder-removed photos=\(controller.snapshot?.photos.count ?? -1)")
            await pause()
            controller.undoManager?.undo()
            await pause()
            let assignments = controller.snapshot?.keywordIdsByPhoto.values.map(\.count).reduce(0, +) ?? -1
            print("BVS10 folder-restored photos=\(controller.snapshot?.photos.count ?? -1) of=\(countBefore) assignments=\(assignments)")
        }
    }

    /// Seeds MIDI bindings (notes 60–63 on channel 0) and prints every anchor
    /// rating/view/keyword change for ~10 s — a virtual source outside the
    /// process sends notes, a virtual destination collects the LED echoes.
    @MainActor
    private static func runMidiChecks(
        _ controller: LibraryController,
        center: CenterViewModel,
        midiMap: MidiMapStore
    ) async {
        guard let peopleId = controller.createKeyword(baseName: "PEOPLE", parentId: nil, groupId: nil),
              controller.createKeyword(baseName: "ANNA", parentId: peopleId, groupId: nil) != nil
        else {
            print("BVMIDI error=vocabulary")
            return
        }
        midiMap.assign(MidiAddress(channel: 0, note: 60)!, to: .app(.rate3))
        midiMap.assign(MidiAddress(channel: 0, note: 61)!, to: .app(.rate0))
        midiMap.assign(MidiAddress(channel: 0, note: 62)!, to: .keyword("PEOPLE > ANNA"))
        midiMap.assign(MidiAddress(channel: 0, note: 63)!, to: .app(.viewSingle))
        print("BVMIDI seeded bindings=\(midiMap.map.bindings.count)")

        var lastReport = ""
        for _ in 0..<100 {
            spinRunLoop()
            try? await Task.sleep(for: .milliseconds(50))
            let anchor = center.selection.anchorId
            let rating = anchor.flatMap { controller.photo(withId: $0)?.rating } ?? -1
            let keywords = anchor.map { id in
                (controller.snapshot?.keywordIdsByPhoto[id] ?? [])
                    .compactMap { controller.snapshot?.keywordTree.path(of: $0) }.sorted()
            } ?? []
            let report = "rating=\(rating) single=\(center.viewMode == .single) keywords=\(keywords)"
            if report != lastReport {
                print("BVMIDI state \(report)")
                lastReport = report
            }
        }
        print("BVMIDI done")
    }

    /// Synchronous on purpose: `RunLoop.run(until:)` is barred from async
    /// contexts, but a sync helper called from one is fine.
    @MainActor
    private static func spinRunLoop() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }


    @MainActor
    private static func runChurn(_ controller: LibraryController) async {
        print("BVCHURN start")
        var iteration = 0
        while true {
            let ids = controller.snapshot?.photos.compactMap(\.id) ?? []
            controller.updateRatings(ids: ids) { rating in (rating + 1) % 6 }
            iteration += 1
            if iteration % 20 == 0 { print("BVCHURN iter=\(iteration)") }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    private static func printCullState(
        _ controller: LibraryController, _ center: CenterViewModel, label: String
    ) {
        let anchor = center.selection.anchorId
        let record = anchor.flatMap { controller.photo(withId: $0) }
        print(
            "BVCULL \(label)",
            "anchor=\(anchor.map(String.init) ?? "none")",
            "pos=\(center.anchorPosition.map(String.init) ?? "-")",
            "visible=\(center.visiblePhotos.count)",
            "rating=\(record.map { String($0.rating) } ?? "-")",
            "orientation=\(record.map { String($0.orientation) } ?? "-")"
        )
    }

    @MainActor
    private static func printImportState(_ controller: LibraryController, label: String) {
        let snapshot = controller.snapshot
        print(
            "BVTEST \(label)",
            "photos=\(snapshot?.photos.count.description ?? "-")",
            "folders=\(snapshot?.folders.count.description ?? "-")",
            "keywords=\(snapshot?.keywordTree.count.description ?? "-")",
            "lastBatch=\(snapshot?.meta.lastImportBatchId.map(String.init) ?? "none")",
            "info=\(quoted(controller.infoMessage))",
            "error=\(quoted(controller.errorMessage))"
        )
    }

    private static func quoted(_ message: String?) -> String {
        message.map { "\"\($0.replacingOccurrences(of: "\n", with: " "))\"" } ?? "none"
    }

    private static func testURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(LibraryDatabase.packageExtension)
    }
    #endif
}
