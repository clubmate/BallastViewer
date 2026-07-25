import Foundation

public enum FolderScanner {
    /// Exactly the eleven extensions of spec §5.3. RAW formats rely on the OS
    /// image framework for decoding; there is no RAW-specific handling.
    public static let acceptedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "tiff", "tif", "raw", "cr2", "nef", "arw", "dng",
    ]

    /// Lists image files in `folderURL`. Recursive by default (fixes C1);
    /// hidden files and package contents are skipped. Per-file errors mean the
    /// file is skipped, never that the scan fails (spec §5.3).
    public static func scan(_ folderURL: URL, recursive: Bool) -> [URL] {
        var options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles, .skipsPackageDescendants,
        ]
        if !recursive {
            options.insert(.skipsSubdirectoryDescendants)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: options
        ) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard acceptedExtensions.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            urls.append(url)
        }
        return urls.sorted { $0.path < $1.path }
    }
}
