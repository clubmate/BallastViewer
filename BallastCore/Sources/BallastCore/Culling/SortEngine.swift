import Foundation

/// The bottom-bar sort options (U9). Session-only — sort resets on launch (Q24).
public enum SortOption: String, CaseIterable, Sendable {
    /// Ascending by real filename (U9 — the original's "Filename" sorted by path).
    case filename
    /// Ascending by full absolute path — the original behaviour (Q10).
    case path
    /// Ascending by EXIF DateTimeOriginal; photos without one sort last (U9).
    case captureDate
    /// Descending — newest import first (spec §11.1).
    case dateAdded
    /// Stable random (Q2).
    case random

    public var displayName: String {
        switch self {
        case .filename: "Filename"
        case .path: "Path"
        case .captureDate: "Capture Date"
        case .dateAdded: "Date Added"
        case .random: "Random"
        }
    }
}

/// Comparators for the visible list. Deliberately none of the sort keys can be
/// changed by a culling mutation (rating, rotation, keywords), so the list
/// never reorders under the user's hands — membership changes are handled by
/// insertion/removal plus the neighbour rule.
public enum SortEngine {
    /// Strict-weak-order comparator for the non-random options. Ties always
    /// break by path, which is unique, so the order is total and stable.
    public static func areInIncreasingOrder(
        _ a: PhotoRecord, _ b: PhotoRecord, by option: SortOption
    ) -> Bool {
        switch option {
        case .filename:
            if a.filename != b.filename { return a.filename < b.filename }
            return a.path < b.path
        case .path:
            return a.path < b.path
        case .captureDate:
            switch (a.captureDate, b.captureDate) {
            case let (dateA?, dateB?) where dateA != dateB:
                return dateA < dateB
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return a.path < b.path
            }
        case .dateAdded:
            if a.dateAdded != b.dateAdded { return a.dateAdded > b.dateAdded }
            return a.path < b.path
        case .random:
            preconditionFailure("random sorts via StableRandomOrder, not a comparator")
        }
    }

    /// Sorts photos for display. For `.random` the caller passes the reconciled
    /// stable order; ids missing from it keep their relative order at the end
    /// (defensive — reconcile first and this never happens).
    public static func sorted(
        _ photos: [PhotoRecord], by option: SortOption, randomOrder: [Int64] = []
    ) -> [PhotoRecord] {
        switch option {
        case .random:
            // A duplicate id in the order must mis-sort, not trap: first wins.
            let position = Dictionary(
                randomOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first }
            )
            return photos.enumerated().sorted { a, b in
                let posA = a.element.id.flatMap { position[$0] } ?? randomOrder.count + a.offset
                let posB = b.element.id.flatMap { position[$0] } ?? randomOrder.count + b.offset
                return posA < posB
            }.map(\.element)
        default:
            return photos.sorted { areInIncreasingOrder($0, $1, by: option) }
        }
    }
}
