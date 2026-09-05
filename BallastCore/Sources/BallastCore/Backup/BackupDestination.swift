import Foundation

/// U53: where a backup goes. A drive (any mounted folder: USB disk, stick,
/// network share) or a server reached with rsync over ssh. Stored app-wide
/// in UserDefaults as JSON.
public struct BackupDestination: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        /// A local folder; the backup root is `<path>/BallastViewerBackup`.
        case drive(path: String)
        /// rsync over ssh; the backup root is `<path>/BallastViewerBackup` on
        /// the server. Password asked per run, never stored.
        case server(host: String, user: String, port: Int, path: String)
    }

    public var id: UUID
    public var kind: Kind

    public init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    public var isServer: Bool {
        if case .server = kind { return true }
        return false
    }

    /// "My Disk/Backups" or "user@host:/backups".
    public var displayName: String {
        switch kind {
        case .drive(let path):
            return path
        case .server(let host, let user, _, let path):
            return "\(user)@\(host):\(path)"
        }
    }

    /// Backup root: the drive folder or the remote path plus the fixed
    /// `BallastViewerBackup` directory.
    public var rootPath: String {
        switch kind {
        case .drive(let path):
            return (BackupPlan.normalized(path) as NSString).appendingPathComponent(BackupPlan.rootFolderName)
        case .server(_, _, _, let path):
            return (BackupPlan.normalized(path) as NSString).appendingPathComponent(BackupPlan.rootFolderName)
        }
    }
}

/// The rsync invocation (U53). One run per library folder pushes exactly
/// the files the plan lists (`--files-from`, relative to the folder) into
/// `<root>/<folder name>/`; a final run pushes the database snapshot from a
/// staging directory. `-t` keeps modification times, so the next run skips
/// unchanged files; nothing is ever deleted on the target.
public enum RsyncCommand {
    public static let executable = "/usr/bin/rsync"

    /// `user@host:path`, the path unquoted (rsync/ssh parse it themselves).
    public static func remoteTarget(user: String, host: String, path: String) -> String {
        "\(user)@\(host):\(path)"
    }

    /// The `--rsh` command: ssh on the given port, unknown hosts accepted on
    /// first contact, exactly one password attempt (a wrong password fails
    /// fast instead of looping through the askpass helper).
    public static func sshCommand(port: Int) -> String {
        "ssh -p \(port) -o StrictHostKeyChecking=accept-new -o NumberOfPasswordPrompts=1"
    }

    /// Arguments for one push. `filesFrom` lists relative paths below
    /// `sourceDir`; `target` is a local directory or `user@host:path`.
    /// Remote targets get their directory created first (`--rsync-path`);
    /// local callers create it themselves.
    public static func arguments(
        filesFrom listPath: String,
        sourceDir: String,
        target: String,
        remotePath: String?,
        sshPort: Int?
    ) -> [String] {
        var args = ["-t", "-v", "--partial", "--files-from=\(listPath)"]
        if let sshPort {
            args.append("--rsh=\(sshCommand(port: sshPort))")
        }
        if let remotePath {
            args.append("--rsync-path=mkdir -p \(shellQuoted(remotePath)) && rsync")
        }
        args.append(sourceDir.hasSuffix("/") ? sourceDir : sourceDir + "/")
        args.append(target.hasSuffix("/") ? target : target + "/")
        return args
    }

    /// Single-quoted for a POSIX shell (the remote `mkdir -p`).
    public static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The transferred files from `-v` output: one relative path per line;
    /// rsync's own chatter ("sending incremental file list", "sent … bytes",
    /// "total size is …", blank lines) is dropped by matching against the
    /// set of paths that were sent.
    public static func transferredPaths(inOutput output: String, expected: Set<String>) -> [String] {
        output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { expected.contains($0) }
    }
}
