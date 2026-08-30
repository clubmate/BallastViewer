/// The app actions (spec §12.2 plus `selectAll`, U33). Every dispatcher must
/// handle all of them exhaustively — the original's fall-through no-op made
/// `ratingUp` / `ratingDown` unreachable from the keyboard (C5).
public enum AppAction: String, CaseIterable, Hashable, Sendable {
    case nextPhoto
    case previousPhoto
    case moveUp
    case moveDown
    case selectAll
    case rotate
    case viewGrid
    case viewSingle
    case toggleViewMode
    case rate0, rate1, rate2, rate3, rate4, rate5
    case ratingUp
    case ratingDown
    case toggleLeftPanel
    case toggleRightPanel
    case toggleBottomPanel

    /// Settings/menu label (spec §12.2 display-name column).
    public var displayName: String {
        switch self {
        case .nextPhoto: "Next Photo"
        case .previousPhoto: "Previous Photo"
        case .moveUp: "Move Up"
        case .moveDown: "Move Down"
        case .selectAll: "Select All"
        case .rotate: "Rotate Selection"
        case .viewGrid: "Grid View"
        case .viewSingle: "Single View"
        case .toggleViewMode: "Toggle View Mode"
        case .rate0: "Rate: Unrated"
        case .rate1: "Rate: 1 Star"
        case .rate2: "Rate: 2 Stars"
        case .rate3: "Rate: 3 Stars"
        case .rate4: "Rate: 4 Stars"
        case .rate5: "Rate: 5 Stars"
        case .ratingUp: "Increase Rating"
        case .ratingDown: "Decrease Rating"
        case .toggleLeftPanel: "Toggle Left Panel"
        case .toggleRightPanel: "Toggle Right Panel"
        case .toggleBottomPanel: "Toggle Bottom Panel"
        }
    }

    /// The star value for the six absolute rating actions, nil otherwise.
    public var absoluteRating: Int? {
        switch self {
        case .rate0: 0
        case .rate1: 1
        case .rate2: 2
        case .rate3: 3
        case .rate4: 4
        case .rate5: 5
        default: nil
        }
    }
}

/// A parsed action string (spec §12.1). Two namespaces:
/// `app:<actionName>` and `keyword:<KEYWORD>` — the keyword text is verbatim,
/// including spaces and `>` path separators.
public enum ActionCommand: Hashable, Sendable {
    case app(AppAction)
    case keyword(String)

    public init?(actionString: String) {
        if actionString.hasPrefix("app:") {
            guard let action = AppAction(rawValue: String(actionString.dropFirst(4))) else {
                return nil
            }
            self = .app(action)
        } else if actionString.hasPrefix("keyword:") {
            let keyword = String(actionString.dropFirst(8))
            guard !keyword.isEmpty else { return nil }
            self = .keyword(keyword)
        } else {
            return nil
        }
    }

    public var actionString: String {
        switch self {
        case .app(let action): "app:\(action.rawValue)"
        case .keyword(let keyword): "keyword:\(keyword)"
        }
    }

    /// The command after the keyword node at `oldPath` was renamed so its
    /// derived path is `newPath` — covers the node itself and its whole
    /// subtree (descendant paths share the prefix). Nil when unaffected.
    /// Without this, a binding would go dark after a rename and the next
    /// press would re-create the old path as a fresh ad-hoc keyword.
    public func renamingKeywordPath(from oldPath: String, to newPath: String) -> ActionCommand? {
        guard case .keyword(let path) = self else { return nil }
        if path == oldPath { return .keyword(newPath) }
        if path.hasPrefix(oldPath + KeywordTree.separator) {
            return .keyword(newPath + path.dropFirst(oldPath.count))
        }
        return nil
    }
}
