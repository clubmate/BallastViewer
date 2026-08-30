import Foundation

/// One GitHub release as the updater needs it: the tag, the monotonically
/// growing build number (the CI versions releases as `v0.1.<commit count>`,
/// mirrored into `CFBundleVersion`), the zip asset and the release notes.
public struct UpdateRelease: Sendable, Equatable {
    public var tag: String
    public var buildNumber: Int
    /// Display version without the tag's `v` prefix ("0.1.94").
    public var version: String
    public var zipURL: URL
    public var notes: String?

    public init(tag: String, buildNumber: Int, version: String, zipURL: URL, notes: String?) {
        self.tag = tag
        self.buildNumber = buildNumber
        self.version = version
        self.zipURL = zipURL
        self.notes = notes
    }
}

public enum UpdateFeedError: Error, Equatable, LocalizedError {
    case malformedFeed
    case noZipAsset

    public var errorDescription: String? {
        switch self {
        case .malformedFeed: return "The release feed could not be read."
        case .noZipAsset: return "The latest release carries no app archive."
        }
    }
}

/// Parses GitHub's `releases/latest` JSON — kept in BallastCore so the
/// version arithmetic is testable without the network.
public enum UpdateFeed {
    public static func parseLatestRelease(_ data: Data) throws -> UpdateRelease {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let build = buildNumber(fromTag: tag)
        else { throw UpdateFeedError.malformedFeed }
        guard let assets = json["assets"] as? [[String: Any]],
              let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
              let urlString = zip["browser_download_url"] as? String,
              let url = URL(string: urlString)
        else { throw UpdateFeedError.noZipAsset }
        return UpdateRelease(
            tag: tag,
            buildNumber: build,
            version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
            zipURL: url,
            notes: (json["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// `v0.1.94` → 94. The last dot component is the commit count — the only
    /// part that grows; comparing it is exact, unlike string-comparing tags.
    public static func buildNumber(fromTag tag: String) -> Int? {
        tag.split(separator: ".").last.flatMap { Int($0) }
    }
}
