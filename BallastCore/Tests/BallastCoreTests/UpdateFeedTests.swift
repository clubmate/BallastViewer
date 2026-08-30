import Foundation
import Testing
@testable import BallastCore

@Suite struct UpdateFeedTests {
    private func feedJSON(
        tag: String = "v0.1.94",
        assets: [[String: String]] = [[
            "name": "BallastViewer-v0.1.94.zip",
            "browser_download_url": "https://github.com/clubmate/BallastViewer/releases/download/v0.1.94/BallastViewer-v0.1.94.zip",
        ]],
        body: String? = "## What's new\n- Things"
    ) -> Data {
        var json: [String: Any] = ["tag_name": tag, "assets": assets]
        if let body { json["body"] = body }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func parsesTagBuildNumberZipAndNotes() throws {
        let release = try UpdateFeed.parseLatestRelease(feedJSON())
        #expect(release.tag == "v0.1.94")
        #expect(release.buildNumber == 94)
        #expect(release.version == "0.1.94")
        #expect(release.zipURL.lastPathComponent == "BallastViewer-v0.1.94.zip")
        #expect(release.notes == "## What's new\n- Things")
    }

    @Test func picksTheZipAmongOtherAssets() throws {
        let release = try UpdateFeed.parseLatestRelease(feedJSON(assets: [
            ["name": "checksums.txt", "browser_download_url": "https://example.com/checksums.txt"],
            ["name": "BallastViewer-v0.1.94.zip", "browser_download_url": "https://example.com/app.zip"],
        ]))
        #expect(release.zipURL.absoluteString == "https://example.com/app.zip")
    }

    @Test func missingZipAssetThrows() {
        #expect(throws: UpdateFeedError.noZipAsset) {
            try UpdateFeed.parseLatestRelease(feedJSON(assets: []))
        }
    }

    @Test func malformedFeedThrows() {
        #expect(throws: UpdateFeedError.malformedFeed) {
            try UpdateFeed.parseLatestRelease(Data("not json".utf8))
        }
        #expect(throws: UpdateFeedError.malformedFeed) {
            try UpdateFeed.parseLatestRelease(feedJSON(tag: "nightly"))
        }
    }

    @Test func buildNumberComesFromTheLastComponent() {
        #expect(UpdateFeed.buildNumber(fromTag: "v0.1.94") == 94)
        #expect(UpdateFeed.buildNumber(fromTag: "v0.2.7") == 7)
        #expect(UpdateFeed.buildNumber(fromTag: "v1") == nil)  // "v1" is not an Int
        #expect(UpdateFeed.buildNumber(fromTag: "v0.1.813") == 813)
    }
}
