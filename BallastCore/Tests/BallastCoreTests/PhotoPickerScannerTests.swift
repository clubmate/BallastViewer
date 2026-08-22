import Foundation
import Testing
@testable import BallastCore

struct PhotoPickerScannerTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("picker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data([0xFF]).write(to: url)
    }

    @Test func listsDirectSubfoldersWithCounts() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root.appendingPathComponent("B/img2.jpg"))
        try touch(root.appendingPathComponent("B/img10.JPG"))
        try touch(root.appendingPathComponent("B/notes.txt"))
        try touch(root.appendingPathComponent("B/_auswahl/img1.jpg"))
        try touch(root.appendingPathComponent("A/x.png"))
        try touch(root.appendingPathComponent("A/deeper/y.png"))
        try touch(root.appendingPathComponent("_auswahl/z.png"))
        try touch(root.appendingPathComponent("loose.jpg"))

        let folders = PhotoPickerScanner.folders(in: root)
        #expect(folders.map(\.name) == ["A", "B"])
        #expect(folders[0].photoCount == 1)   // deeper/ is not counted
        #expect(folders[0].pickedCount == 0)
        #expect(folders[1].photoCount == 2)   // _auswahl and notes.txt excluded
        #expect(folders[1].pickedCount == 1)

        let photos = PhotoPickerScanner.photos(in: folders[1].url)
        #expect(photos.map(\.lastPathComponent) == ["img2.jpg", "img10.JPG"])
    }
}
