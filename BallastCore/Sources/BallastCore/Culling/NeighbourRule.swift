/// Q1 — the neighbour rule (spec §10.4), the app's most important interaction
/// detail. When the current photo drops out of the visible list (its rating or
/// keywords no longer match the active filter), do NOT jump to the top:
/// select the nearest surviving photo *after* it in the previous order,
/// failing that the nearest *before* it, failing that the first photo of the
/// new list, failing that nothing.
public enum NeighbourRule {
    /// - Parameters:
    ///   - anchorId: the photo that was current before the change.
    ///   - previousOrder: the visible order *before* the change.
    ///   - newOrder: the visible order *after* the change.
    /// - Returns: the id to select, or nil when the new list is empty.
    ///   If the anchor is still visible it is returned unchanged.
    public static func nextAnchor(
        for anchorId: Int64,
        previousOrder: [Int64],
        newOrder: [Int64]
    ) -> Int64? {
        let surviving = Set(newOrder)
        guard !surviving.contains(anchorId) else { return anchorId }
        guard let removedIndex = previousOrder.firstIndex(of: anchorId) else {
            return newOrder.first
        }
        for index in (removedIndex + 1)..<previousOrder.count
        where surviving.contains(previousOrder[index]) {
            return previousOrder[index]
        }
        for index in stride(from: removedIndex - 1, through: 0, by: -1)
        where surviving.contains(previousOrder[index]) {
            return previousOrder[index]
        }
        return newOrder.first
    }
}
