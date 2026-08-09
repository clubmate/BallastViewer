import AppKit
import BallastCore

/// Headless lifecycle checks, driven by environment variables so acceptance
/// criteria can be verified from the CLI (the sandboxed container's temp
/// directory is used for test libraries). Debug builds only; inert unless
/// BV_TEST is set.
///
/// Hooks: BV_TEST_CREATE=<name> · BV_TEST_OPEN=<name> · BV_TEST_IMPORT=<abs path>
/// (twice with BV_TEST_RESCAN=1) · BV_TEST_NONRECURSIVE=1 · BV_TEST_REMOVE=<abs path>
/// · BV_TEST_CULL=1 (step-6 acceptance flow) · BV_TEST_KEYWORDS=1 (step-8
/// acceptance flow) · BV_TEST_STEP9=1 (search + keyword-shortcut flow) ·
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
        midiMap: MidiMapStore
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
            let paths = snapshot.queryFacts(forPhotoId: id).keywordPaths.sorted()
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
        print("BVS10 before-save \(anchorState())")
        dumpAll("before-save")

        // Save → the file carries the library's values (D1 via app path).
        await controller.saveMetadataToFiles()
        print("BVS10 save info=\(quoted(controller.infoMessage))")
        controller.infoMessage = nil
        if let id = center.selection.anchorId, let record = controller.photo(withId: id) {
            let fileValues = MetadataReader.read(from: URL(fileURLWithPath: record.path))
            print("BVS10 file rating=\(fileValues.rating) orientation=\(fileValues.orientation) keywords=\(fileValues.keywords)")
        }

        // Diverge the library, prepare unused vocabulary, then Load.
        dispatcher.dispatch(.app(.rate2))
        await pause()
        print("BVS10 stack after-rate2 top=\(controller.undoManager?.undoActionName ?? "-") canUndo=\(controller.undoManager?.canUndo ?? false)")
        dumpAll("after-rate2")
        controller.createKeyword(baseName: "UNUSED", parentId: nil, groupId: nil)
        await pause()
        await controller.loadMetadataFromFiles()
        print("BVS10 stack after-load top=\(controller.undoManager?.undoActionName ?? "-")")
        print("BVS10 load info=\(quoted(controller.infoMessage)) \(anchorState())")
        controller.infoMessage = nil
        let hasUnused = controller.snapshot?.keywordTree.allPaths().contains("UNUSED") ?? false
        print("BVS10 d2 unusedSurvivesLoad=\(hasUnused)")

        // Undo the load (one step) → rating back to 2; redo → 4 again.
        // Undo groups close per runloop turn — pause so the group is closed
        // before undoing (real usage: one gesture per event).
        await pause()
        controller.undoManager?.undo()
        print("BVS10 undo-load \(anchorState())")
        await pause()
        controller.undoManager?.redo()
        print("BVS10 redo-load \(anchorState())")
        await pause()

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
