import Foundation
import GRDB

/// A library photo as the Lightroom matcher sees it — id plus stored path.
public struct LightroomLibraryPhoto: Sendable {
    public var id: Int64
    public var path: String

    public init(id: Int64, path: String) {
        self.id = id
        self.path = path
    }
}

public struct LightroomMatch: Sendable, Equatable {
    public var photoId: Int64
    public var entry: LightroomPhotoEntry

    public init(photoId: Int64, entry: LightroomPhotoEntry) {
        self.photoId = photoId
        self.entry = entry
    }
}

public struct LightroomMatchResult: Sendable {
    public var matches: [LightroomMatch] = []
    public var pathMatches = 0
    public var filenameMatches = 0
    /// Catalog entries with no corresponding library photo.
    public var unmatched = 0
    /// Catalog entries skipped because the assignment was not unique — a
    /// wrong merge would put foreign keywords on a photo AND write them into
    /// its file, so ambiguity always loses to caution.
    public var ambiguous = 0
    /// Library photos involved in those ambiguous cases — candidates that may
    /// have deserved metadata but were skipped. The import tags them for
    /// manual review (issue keyword + smart collection).
    public var ambiguousPhotoIds: [Int64] = []

    public init() {}
}

/// Pairs Lightroom catalog entries with library photos. Two passes:
/// 1. exact path (case-insensitive, NFC-normalized — Lightroom's stored paths
///    can differ byte-wise from the scanner's for accented names),
/// 2. bare filename for photos that moved folders since Lightroom saw them —
///    only when the filename is unique among the remaining entries AND the
///    remaining photos.
public enum LightroomMatcher {
    public static func match(
        entries: [LightroomPhotoEntry], photos: [LightroomLibraryPhoto]
    ) -> LightroomMatchResult {
        var result = LightroomMatchResult()

        var photoIdsByPath: [String: [Int64]] = [:]
        for photo in photos {
            photoIdsByPath[key(photo.path), default: []].append(photo.id)
        }

        var matchedPhotoIds: Set<Int64> = []
        var ambiguousPhotoIds: Set<Int64> = []
        var pending: [LightroomPhotoEntry] = []
        for entry in entries {
            guard let ids = photoIdsByPath[key(entry.path)] else {
                pending.append(entry)
                continue
            }
            if ids.count == 1, !matchedPhotoIds.contains(ids[0]) {
                result.matches.append(LightroomMatch(photoId: ids[0], entry: entry))
                result.pathMatches += 1
                matchedPhotoIds.insert(ids[0])
            } else {
                // Several photos fold to the same path, or a duplicate entry
                // hit an already-taken photo.
                result.ambiguous += 1
                ambiguousPhotoIds.formUnion(ids)
            }
        }

        var entryIndicesByFilename: [String: [Int]] = [:]
        for (index, entry) in pending.enumerated() {
            entryIndicesByFilename[filenameKey(entry.path), default: []].append(index)
        }
        var photoIdsByFilename: [String: [Int64]] = [:]
        for photo in photos where !matchedPhotoIds.contains(photo.id) {
            photoIdsByFilename[filenameKey(photo.path), default: []].append(photo.id)
        }
        for (filename, entryIndices) in entryIndicesByFilename {
            let candidates = photoIdsByFilename[filename] ?? []
            if entryIndices.count == 1, candidates.count == 1 {
                result.matches.append(
                    LightroomMatch(photoId: candidates[0], entry: pending[entryIndices[0]])
                )
                result.filenameMatches += 1
            } else if candidates.isEmpty {
                result.unmatched += entryIndices.count
            } else {
                result.ambiguous += entryIndices.count
                ambiguousPhotoIds.formUnion(candidates)
            }
        }
        result.ambiguousPhotoIds = ambiguousPhotoIds.sorted()
        return result
    }

    /// The one comparison key both sides fold to: NFC first (HFS+/APFS store
    /// decomposed names), then the canonical case fold.
    static func key(_ path: String) -> String {
        CaseInsensitiveMatch.fold(path.precomposedStringWithCanonicalMapping)
    }

    static func filenameKey(_ path: String) -> String {
        key((path as NSString).lastPathComponent)
    }
}

public struct LightroomMergeSummary: Sendable, Equatable {
    /// Photos whose rating or keyword set actually changed — these carry
    /// `needsFileWrite` and must be handed to the write-through by the caller.
    public var changedPhotoIds: [Int64] = []
    public var ratingsApplied = 0
    public var assignmentsAdded = 0
    public var keywordsCreated = 0

    public init() {}
}

/// Applies matched Lightroom metadata in one transaction: additive keyword
/// merge (never removes existing assignments), Lightroom's rating wins where
/// it has one (nil = unrated there = leave the library value alone). No-op
/// matches are detected here so unchanged photos are NOT flagged for a file
/// rewrite — rerunning the same import must not touch a single file.
public enum LightroomImportDAO {
    public static func merge(
        _ matches: [LightroomMatch], in db: Database
    ) throws -> LightroomMergeSummary {
        var summary = LightroomMergeSummary()
        guard !matches.isEmpty else { return summary }

        let keywordCache = try KeywordPathCache(preloading: db)
        let keywordIdsByPhoto = try PhotoDAO.fetchKeywordIdsByPhoto(db)
        var ratingById: [Int64: Int] = [:]
        let cursor = try Row.fetchCursor(db, sql: "SELECT id, rating FROM photo")
        while let row = try cursor.next() {
            ratingById[row[0]] = row[1]
        }

        var changed: Set<Int64> = []
        var ratingUpdates: [(photoId: Int64, rating: Int)] = []
        for match in matches {
            // The snapshot the match was computed from can lag the database;
            // a photo deleted in between is skipped, never resurrected.
            guard let currentRating = ratingById[match.photoId] else { continue }

            var additions: [Int64] = []
            for components in match.entry.keywordPaths {
                let normalized = components.map(KeywordDAO.normalize).filter { !$0.isEmpty }
                guard !normalized.isEmpty else { continue }
                let (leafId, created) = try KeywordDAO.ensurePathCollectingCreated(
                    normalized, groupId: nil, cache: keywordCache, in: db
                )
                summary.keywordsCreated += created.count
                let existing = keywordIdsByPhoto[match.photoId] ?? []
                if !existing.contains(leafId), !additions.contains(leafId) {
                    additions.append(leafId)
                }
            }
            for leafId in additions {
                try PhotoDAO.assignKeyword(leafId, toPhotoIds: [match.photoId], in: db)
            }
            if !additions.isEmpty {
                summary.assignmentsAdded += additions.count
                changed.insert(match.photoId)
            }

            if let lightroomRating = match.entry.rating {
                let rating = max(0, min(5, lightroomRating))
                if rating != currentRating {
                    ratingUpdates.append((photoId: match.photoId, rating: rating))
                    changed.insert(match.photoId)
                }
            }
        }

        try PhotoDAO.setRatings(ratingUpdates, in: db)
        summary.ratingsApplied = ratingUpdates.count
        // Flagged inside the SAME transaction: if the app dies before the
        // write-through runs, the next library open re-queues these files.
        summary.changedPhotoIds = changed.sorted()
        try PhotoDAO.setNeedsFileWrite(true, forPhotoIds: summary.changedPhotoIds, in: db)
        return summary
    }

    /// Tags the library photos an ambiguous match skipped with a review
    /// keyword (top-level, ad-hoc) and collects them in a smart collection
    /// (`keyword equals <name>`) inside `groupName` — both find-or-create, so
    /// a rerun reuses them. Returns the NEWLY tagged photo ids (already
    /// flagged `needsFileWrite`; the caller schedules the write-through).
    /// Deleting the keyword afterwards cleans up fully — the collection then
    /// simply goes empty until it is deleted too.
    public static func markIssues(
        photoIds: [Int64],
        keywordName: String,
        groupName: String,
        collectionName: String,
        in db: Database
    ) throws -> [Int64] {
        guard !photoIds.isEmpty else { return [] }
        let name = KeywordDAO.normalize(keywordName)
        let keywordId = try KeywordDAO.ensurePath([name], groupId: nil, in: db)

        let existingPhotoIds = Set(try Int64.fetchAll(db, sql: "SELECT id FROM photo"))
        let alreadyTagged = Set(try Int64.fetchAll(
            db, sql: "SELECT photoId FROM photoKeyword WHERE keywordId = ?",
            arguments: [keywordId]
        ))
        let newlyTagged = photoIds.filter {
            existingPhotoIds.contains($0) && !alreadyTagged.contains($0)
        }
        try PhotoDAO.assignKeyword(keywordId, toPhotoIds: newlyTagged, in: db)
        try PhotoDAO.setNeedsFileWrite(true, forPhotoIds: newlyTagged, in: db)

        let group = try SmartGroupRecord
            .filter(Column("name") == groupName).fetchOne(db)
            ?? CollectionDAO.createGroup(name: groupName, in: db)
        let collection = try SmartCollectionRecord
            .filter(Column("groupId") == group.id! && Column("name") == collectionName)
            .fetchOne(db)
            ?? CollectionDAO.createCollection(name: collectionName, inGroup: group.id!, in: db)
        try CollectionDAO.saveRules(
            [(type: RuleType.keyword.rawValue, operation: RuleOperator.equals.rawValue, value: name)],
            forCollection: collection.id!,
            in: db
        )
        return newlyTagged
    }
}
