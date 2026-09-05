import Foundation
import GRDB
import Testing
@testable import BallastCore

/// U53: backup plan layout, destination naming, rsync argument building,
/// the reminder schedule, the database snapshot and Relink Folder.
struct BackupTests {
    private func folder(_ id: Int64, _ path: String) -> FolderRecord {
        FolderRecord(id: id, path: path, bookmark: nil, recursive: true)
    }

    private func photo(_ folderId: Int64, _ path: String) -> PhotoRecord {
        PhotoRecord(folderId: folderId, path: path)
    }

    @Test func flatLayoutUsesFolderNames() {
        let folders = [folder(1, "/Users/x/Pictures/2008/"), folder(2, "/Volumes/Disk/2009")]
        let photos = [
            photo(1, "/Users/x/Pictures/2008/a.jpg"),
            photo(1, "/Users/x/Pictures/2008/sub/b.jpg"),
            photo(2, "/Volumes/Disk/2009/c.jpg"),
        ]
        let plan = BackupPlan.make(folders: folders, photos: photos)
        #expect(plan.folderNames == [1: "2008", 2: "2009"])
        #expect(plan.items.map(\.relativePath) == ["2008/a.jpg", "2008/sub/b.jpg", "2009/c.jpg"])
        #expect(plan.items(inFolder: 1, folders: folders).count == 2)
    }

    @Test func sameNamedFoldersGetTheirParentPrepended() {
        let folders = [folder(1, "/Platte1/2008"), folder(2, "/Platte2/2008"), folder(3, "/Platte1/2009")]
        let names = BackupPlan.targetNames(for: folders)
        #expect(names == [1: "Platte1 - 2008", 2: "Platte2 - 2008", 3: "2009"])
    }

    @Test func identicalParentsAreNumbered() {
        let folders = [folder(1, "/A/X/2008"), folder(2, "/B/X/2008")]
        let names = BackupPlan.targetNames(for: folders)
        #expect(Set(names.values) == ["X - 2008", "X - 2008 (2)"])
    }

    @Test func photoOutsideItsFolderFallsBackToFilename() {
        let plan = BackupPlan.make(
            folders: [folder(1, "/a/b")],
            photos: [PhotoRecord(folderId: 1, path: "/elsewhere/c.jpg")]
        )
        #expect(plan.items.map(\.relativePath) == ["b/c.jpg"])
    }

    @Test func destinationRootsAppendTheFixedFolder() {
        let drive = BackupDestination(kind: .drive(path: "/Volumes/USB/"))
        #expect(drive.rootPath == "/Volumes/USB/BallastViewerBackup")
        #expect(drive.displayName == "/Volumes/USB/")
        let server = BackupDestination(kind: .server(host: "nas", user: "me", port: 2222, path: "/srv/backup"))
        #expect(server.rootPath == "/srv/backup/BallastViewerBackup")
        #expect(server.displayName == "me@nas:/srv/backup")
        #expect(server.isServer && !drive.isServer)
    }

    @Test func destinationsRoundTripThroughJSON() throws {
        let list = [
            BackupDestination(kind: .drive(path: "/Volumes/USB")),
            BackupDestination(kind: .server(host: "nas", user: "me", port: 22, path: "/srv")),
        ]
        let data = try JSONEncoder().encode(list)
        #expect(try JSONDecoder().decode([BackupDestination].self, from: data) == list)
    }

    @Test func rsyncArgumentsForServerAndLocal() {
        let remote = RsyncCommand.arguments(
            filesFrom: "/tmp/list.txt", sourceDir: "/Users/x/2008",
            target: RsyncCommand.remoteTarget(user: "me", host: "nas", path: "/srv/BallastViewerBackup/Platte1 - 2008"),
            remotePath: "/srv/BallastViewerBackup/Platte1 - 2008", sshPort: 2222
        )
        #expect(remote == [
            "-t", "-v", "--partial-dir=.bvpartial", "--files-from=/tmp/list.txt",
            "--rsh=ssh -p 2222 -o StrictHostKeyChecking=accept-new -o NumberOfPasswordPrompts=1",
            "--rsync-path=mkdir -p /srv/BallastViewerBackup/Platte1\\ -\\ 2008 && rsync",
            "/Users/x/2008/", "me@nas:/srv/BallastViewerBackup/Platte1\\ -\\ 2008/",
        ])
        let local = RsyncCommand.arguments(
            filesFrom: "/tmp/list.txt", sourceDir: "/Users/x/2008/", target: "/Volumes/USB/BallastViewerBackup/2008",
            remotePath: nil, sshPort: nil
        )
        #expect(local == ["-t", "-v", "--partial-dir=.bvpartial", "--files-from=/tmp/list.txt", "/Users/x/2008/", "/Volumes/USB/BallastViewerBackup/2008/"])
    }

    @Test func shellEscapingCoversMetacharactersAndKeepsUnicode() {
        #expect(RsyncCommand.shellEscaped("/srv/Urlaub 2008") == "/srv/Urlaub\\ 2008")
        #expect(RsyncCommand.shellEscaped("it's $x & y|z;(w)*?[a]\"q\"") == "it\\'s\\ \\$x\\ \\&\\ y\\|z\\;\\(w\\)\\*\\?\\[a\\]\\\"q\\\"")
        #expect(RsyncCommand.shellEscaped("/backup/Fotos Müller/2008") == "/backup/Fotos\\ Müller/2008")
        #expect(RsyncCommand.isRemotePathSafe("/srv/Urlaub 2008"))
        #expect(!RsyncCommand.isRemotePathSafe("/srv/Urlaub  2008"))
        #expect(!RsyncCommand.isRemotePathSafe("/srv/a\nb"))
        #expect(!RsyncCommand.isRemotePathSafe(""))
        #expect(RsyncCommand.isListableName("a b/c.jpg"))
        #expect(!RsyncCommand.isListableName("a\nb.jpg"))
        #expect(RsyncCommand.isAuthenticationFailure("me@nas: Permission denied (publickey,password)."))
        #expect(RsyncCommand.isAuthenticationFailure("Permission denied, please try again."))
        #expect(!RsyncCommand.isAuthenticationFailure("rsync: mkstemp failed: Permission denied (13)"))
    }

    @Test func folderNamesAreSanitisedForTheRemoteShell() {
        let names = BackupPlan.targetNames(for: [folder(1, "/x/Urlaub   2008\t"), folder(2, "/y/Urlaub   2008")])
        #expect(Set(names.values) == ["x - Urlaub 2008", "y - Urlaub 2008"])
    }

    @Test func transferredPathsIgnoreRsyncChatter() {
        let output = """
            building file list ... done
            a.jpg
            sub/b.jpg
             leading space.jpg

            sent 1234 bytes  received 42 bytes  2552.00 bytes/sec
            total size is 999  speedup is 0.78
            """
        let found = RsyncCommand.transferredPaths(inOutput: output, expected: ["a.jpg", "sub/b.jpg", "c.jpg", " leading space.jpg"])
        #expect(found == ["a.jpg", "sub/b.jpg", " leading space.jpg"])
    }

    @Test func scheduleIsDueAfterIntervalUnlessSnoozed() {
        let now = Date(timeIntervalSince1970: 100_000_000)
        let day: TimeInterval = 86_400
        #expect(BackupSchedule.isDue(lastBackup: nil, intervalDays: 30, snoozedUntil: nil, now: now))
        #expect(!BackupSchedule.isDue(lastBackup: now - 29 * day, intervalDays: 30, snoozedUntil: nil, now: now))
        #expect(BackupSchedule.isDue(lastBackup: now - 31 * day, intervalDays: 30, snoozedUntil: nil, now: now))
        #expect(!BackupSchedule.isDue(lastBackup: now - 31 * day, intervalDays: 30, snoozedUntil: now + day, now: now))
        #expect(BackupSchedule.isDue(lastBackup: now - 31 * day, intervalDays: 30, snoozedUntil: now - 1, now: now))
        #expect(!BackupSchedule.isDue(lastBackup: nil, intervalDays: 0, snoozedUntil: nil, now: now))
    }

    // MARK: Database snapshot + relink

    private func temporaryLibrary() throws -> (LibraryDatabase, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupTests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("Lib.ballastlib")
        let database = try LibraryDatabase.create(at: url)
        return (database, dir)
    }

    @Test func snapshotIsASelfContainedConsistentCopy() throws {
        let (database, dir) = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: dir) }
        try database.pool.write { db in
            let folder = try ImportDAO.registerFolder(path: "/p/2008", bookmark: nil, recursive: true, in: db)
            var photo = PhotoRecord(folderId: folder.id!, path: "/p/2008/a.jpg")
            photo.rating = 4
            try photo.insert(db)
        }
        let copy = dir.appendingPathComponent("copy/Lib.ballastlib/library.sqlite")
        try database.snapshotDatabase(to: copy)
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(!FileManager.default.fileExists(atPath: copy.path + "-wal"))
        let reopened = try LibraryDatabase.open(at: copy.deletingLastPathComponent())
        let photos = try reopened.pool.read { try PhotoDAO.fetchAll($0) }
        #expect(photos.map(\.rating) == [4])
        try reopened.pool.close()
        try database.pool.close()
    }

    @Test func relinkRewritesPrefixOnlyForThatFolder() throws {
        let (database, dir) = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (moved, other) = try database.pool.write { db -> (Int64, Int64) in
            let a = try ImportDAO.registerFolder(path: "/old/2008/", bookmark: nil, recursive: true, in: db)
            let b = try ImportDAO.registerFolder(path: "/old/2008-extra", bookmark: nil, recursive: true, in: db)
            var p1 = PhotoRecord(folderId: a.id!, path: "/old/2008/a.jpg"); p1.rating = 3
            var p2 = PhotoRecord(folderId: a.id!, path: "/old/2008/sub/b\u{0308}.jpg")
            var p3 = PhotoRecord(folderId: b.id!, path: "/old/2008-extra/c.jpg")
            try p1.insert(db); try p2.insert(db); try p3.insert(db)
            return (a.id!, b.id!)
        }
        let changed = try database.pool.write { db in
            try ImportDAO.relinkFolder(moved, to: "/Volumes/USB/BallastViewerBackup/2008", bookmark: Data([1]), in: db)
        }
        #expect(changed == 2)
        let snapshot = try database.pool.read { try LibrarySnapshot.load($0) }
        let folderA = snapshot.folders.first { $0.id == moved }
        #expect(folderA?.path == "/Volumes/USB/BallastViewerBackup/2008")
        #expect(folderA?.bookmark == Data([1]))
        #expect(snapshot.folders.first { $0.id == other }?.path == "/old/2008-extra")
        let paths = Set(snapshot.photos.map(\.path))
        #expect(paths == [
            "/Volumes/USB/BallastViewerBackup/2008/a.jpg",
            "/Volumes/USB/BallastViewerBackup/2008/sub/b\u{0308}.jpg",
            "/old/2008-extra/c.jpg",
        ])
        #expect(snapshot.photos.first { $0.path.hasSuffix("a.jpg") }?.rating == 3)
        try database.pool.close()
    }
}
