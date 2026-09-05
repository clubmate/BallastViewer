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
///
/// Remote paths are BACKSLASH-escaped, never quoted: macOS ships openrsync,
/// which tokenises `--rsync-path` on whitespace, strips single quotes and
/// hands the words to ssh, which re-joins them with single spaces for the
/// remote login shell — a quoted `'/srv/Urlaub 2008'` arrives as two
/// arguments (review finding 2026-09-05). Backslashes survive that trip.
/// Runs of several spaces would still collapse, so `isRemotePathSafe`
/// rejects those (and control characters) up front.
public enum RsyncCommand {
    public static let executable = "/usr/bin/rsync"

    /// `user@host:path` with the path escaped for the remote shell.
    public static func remoteTarget(user: String, host: String, path: String) -> String {
        "\(user)@\(host):\(shellEscaped(path))"
    }

    /// Characters that pass through the remote shell unescaped.
    private static let plainCharacters: Set<Character> = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:@%+=,~"
    )

    /// Backslash-escapes everything the remote POSIX shell would interpret
    /// (spaces, quotes, `$`, `&`, `|`, `;`, globs, parentheses …).
    public static func shellEscaped(_ s: String) -> String {
        var out = ""
        for character in s {
            if plainCharacters.contains(character) || character.unicodeScalars.allSatisfy({ $0.value > 127 }) {
                out.append(character)
            } else {
                out.append("\\")
                out.append(character)
            }
        }
        return out
    }

    /// A remote path (or folder name on the server) survives the argv →
    /// ssh → shell trip only without runs of whitespace or control
    /// characters (newline, tab, …).
    public static func isRemotePathSafe(_ s: String) -> Bool {
        guard !s.isEmpty, !s.contains("  ") else { return false }
        return !s.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }

    /// The `--rsh` command: ssh on the given port, unknown hosts accepted on
    /// first contact, exactly one password attempt (a wrong password fails
    /// fast instead of looping through the askpass helper).
    public static func sshCommand(port: Int) -> String {
        "ssh -p \(port) -o StrictHostKeyChecking=accept-new -o NumberOfPasswordPrompts=1"
    }

    /// Where an interrupted transfer is parked (a cancelled run must never
    /// leave a truncated photo under its final name).
    public static let partialDirectory = ".bvpartial"

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
        var args = ["-t", "-v", "--partial-dir=\(partialDirectory)", "--files-from=\(listPath)"]
        if let sshPort {
            args.append("--rsh=\(sshCommand(port: sshPort))")
        }
        if let remotePath {
            args.append("--rsync-path=mkdir -p \(shellEscaped(remotePath)) && rsync")
        }
        args.append(sourceDir.hasSuffix("/") ? sourceDir : sourceDir + "/")
        args.append(target.hasSuffix("/") ? target : target + "/")
        return args
    }

    /// The transferred files from `-v` output: one relative path per line,
    /// verbatim (a name with a leading or trailing space must still match);
    /// rsync's own chatter ("sending incremental file list", "sent … bytes",
    /// "total size is …", blank lines) is dropped by matching against the
    /// set of paths that were sent.
    public static func transferredPaths(inOutput output: String, expected: Set<String>) -> [String] {
        output.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { expected.contains($0) }
    }

    /// A file name rsync cannot receive through `--files-from` (openrsync has
    /// no `--from0`): a line break would be read as two names.
    public static func isListableName(_ relativePath: String) -> Bool {
        !relativePath.contains("\n") && !relativePath.contains("\r")
    }

    /// ssh's own authentication failure — NOT a remote file permission
    /// error, which rsync reports as "Permission denied (13)" per file.
    public static func isAuthenticationFailure(_ stderr: String) -> Bool {
        // ssh: "Permission denied (publickey,password)." — the parenthesis
        // lists auth methods; rsync's per-file errno form is "(13)".
        stderr.contains("Permission denied, please try again")
            || stderr.range(of: #"Permission denied \([a-z][a-z,\-]*\)"#, options: .regularExpression) != nil
    }
}
