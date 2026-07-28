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
/// acceptance flow) · BV_TEST_SINGLE=1 (single view, no quit) ·
/// BV_TEST_ROTATE=<n> (rotate anchor n times, no quit) · BV_TEST_CLOSE=1
/// · BV_TEST_QUIT=1
enum TestHooks {
    @MainActor
    static func runIfRequested(
        _ controller: LibraryController,
        center: CenterViewModel,
        sidebar: SidebarViewModel,
        dispatcher: ActionDispatcher
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
            controller.createLibrary(at: url)
        }
        if let name = env["BV_TEST_OPEN"] {
            controller.openLibrary(at: testURL(named: name))
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
            "recents=\(controller.recentLibraries.count)",
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
            controller.openLibrary(at: url)
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
            controller.openLibrary(at: url)
        }
        let restoredFirst = controller.snapshot?.photos.compactMap(\.id)
            .first(where: { controller.snapshot?.keywordIdsByPhoto[$0]?.isEmpty == false })
        print(
            "BVKEY persisted assignments=\(controller.snapshot?.keywordIdsByPhoto.values.map(\.count).reduce(0, +) ?? -1)",
            "keywords=\(controller.snapshot?.keywordTree.count ?? -1)",
            "firstCarrierChips=\(describe(restoredFirst.map { chips(for: [$0]) } ?? []))"
        )
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
