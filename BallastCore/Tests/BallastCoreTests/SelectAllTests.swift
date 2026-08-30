import Testing
@testable import BallastCore

@Suite struct SelectAllTests {
    @Test func selectAllKeepsAContainedAnchor() {
        var selection = SelectionModel()
        selection.selectSingle(2)
        selection.selectAll([1, 2, 3])
        #expect(selection.selectedIds == [1, 2, 3])
        #expect(selection.anchorId == 2)
    }

    @Test func selectAllFallsBackToTheFirstId() {
        var selection = SelectionModel()
        selection.selectSingle(99)
        selection.selectAll([1, 2, 3])
        #expect(selection.anchorId == 1)
        selection.selectAll([])
        #expect(selection.selectedIds.isEmpty)
        #expect(selection.anchorId == nil)
    }

    @Test func defaultKeyMapBindsCmdAToSelectAll() {
        #expect(KeyMap.defaults.bindings["cmd+a"] == "app:selectAll")
        #expect(AppAction.selectAll.displayName == "Select All")
    }
}
