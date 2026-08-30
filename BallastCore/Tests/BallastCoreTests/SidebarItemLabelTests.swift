import Testing
@testable import BallastCore

/// U44: the single-view footer names the active filter with the sidebar's own
/// wording — collection chains root-first, keyword paths as stored.
@Suite struct SidebarItemLabelTests {
    private var tree: KeywordTree {
        KeywordTree(records: [
            KeywordRecord(id: 1, name: "PEOPLE"),
            KeywordRecord(id: 2, parentId: 1, name: "ANNA"),
        ])
    }

    private var collections: [SmartCollectionRecord] {
        [
            SmartCollectionRecord(id: 10, groupId: 1, name: "TRIPS", sortOrder: 0),
            SmartCollectionRecord(id: 11, groupId: 1, parentId: 10, name: "2009", sortOrder: 0),
        ]
    }

    private func name(_ item: SidebarItem) -> String {
        item.displayName(collections: collections, keywordTree: tree)
    }

    @Test func pseudoCollectionsUseSidebarWording() {
        #expect(name(.allPhotos) == "ALL PHOTOS")
        #expect(name(.lastImport) == "LAST IMPORT")
        #expect(name(.rating(0)) == "UNRATED")
        #expect(name(.rating(1)) == "★")
        #expect(name(.rating(4)) == "★★★★")
    }

    @Test func collectionRendersAncestorChainRootFirst() {
        #expect(name(.collection(10)) == "TRIPS")
        #expect(name(.collection(11)) == "TRIPS > 2009")
    }

    @Test func keywordRendersFullPath() {
        #expect(name(.keyword(2)) == "PEOPLE > ANNA")
    }

    @Test func unknownIdsFallBackInsteadOfCrashing() {
        #expect(name(.collection(99)) == "?")
        #expect(name(.keyword(99)) == "?")
    }

    @Test func parentCycleInHandEditedDataTerminates() {
        let cyclic = [
            SmartCollectionRecord(id: 1, groupId: 1, parentId: 2, name: "A", sortOrder: 0),
            SmartCollectionRecord(id: 2, groupId: 1, parentId: 1, name: "B", sortOrder: 0),
        ]
        let label = SidebarItem.collection(1).displayName(collections: cyclic, keywordTree: tree)
        #expect(label == "B > A")
    }
}
