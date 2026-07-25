import Foundation
import GRDB
import Testing
@testable import BallastCore

/// Acceptance gate for step 2: a 50k-photo library must load into memory in
/// well under a second — this bounds app-startup time (spec §16.5 replacement).
@Suite struct PerformanceTests {
    @Test func fiftyThousandPhotosInsertAndLoadFast() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(LibraryDatabase.packageExtension)
        defer { try? FileManager.default.removeItem(at: url) }

        let library = try LibraryDatabase.create(at: url)
        let clock = ContinuousClock()

        let insertDuration = try clock.measure {
            try library.pool.write { db in
                let folderId = try insertFolder(db, path: "/tmp/shoot")
                let annaId = try KeywordDAO.ensurePath(["PEOPLE", "ANNA"], groupId: nil, in: db)
                let year = try KeywordDAO.ensurePath(["YEAR", "2026"], groupId: nil, in: db)
                let now = Date()
                for i in 0..<50_000 {
                    var photo = PhotoRecord(
                        folderId: folderId,
                        path: "/tmp/shoot/IMG_\(String(format: "%06d", i)).jpg",
                        rating: i % 6,
                        dateAdded: now
                    )
                    try photo.insert(db)
                    // Every third photo tagged → 33k assignments, realistic join load.
                    if i % 3 == 0 {
                        try PhotoDAO.assignKeyword(
                            i % 2 == 0 ? annaId : year,
                            toPhotoIds: [photo.id!],
                            in: db
                        )
                    }
                }
            }
        }

        var snapshot: LibrarySnapshot?
        let loadDuration = try clock.measure {
            snapshot = try library.pool.read { try LibrarySnapshot.load($0) }
        }

        print("50k insert: \(insertDuration), snapshot load: \(loadDuration)")
        #expect(snapshot?.photos.count == 50_000)
        #expect(snapshot?.keywordIdsByPhoto.count == 16_667)
        #expect(loadDuration < .seconds(1))
        #expect(insertDuration < .seconds(15))
    }
}
