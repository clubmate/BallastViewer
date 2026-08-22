import Foundation

/// One sub-folder of the Photo Picker root: how many photos are still waiting
/// and how many were already moved into its `_auswahl` sub-folder.
public struct PickerFolder: Identifiable, Equatable, Sendable {
    public let url: URL
    public let name: String
    public var photoCount: Int
    public var pickedCount: Int

    public var id: String { url.path }

    public init(url: URL, name: String, photoCount: Int, pickedCount: Int) {
        self.url = url
        self.name = name
        self.photoCount = photoCount
        self.pickedCount = pickedCount
    }
}

/// File-system reads for the Photo Picker utility. Entirely separate from the
/// library import path: no database, no recursion, no metadata — only the
/// direct sub-folders of a root and the image files directly inside them.
public enum PhotoPickerScanner {
    /// Name of the per-folder selection sub-folder the picker moves files into.
    public static let selectionFolderName = "_auswahl"

    /// Direct sub-folders of `root` (hidden folders and `_auswahl` itself are
    /// skipped), sorted by name, with their photo and selection counts.
    public static func folders(in root: URL) -> [PickerFolder] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []
        return contents
            .filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    && $0.lastPathComponent != selectionFolderName
            }
            .map { url in
                PickerFolder(
                    url: url,
                    name: url.lastPathComponent,
                    photoCount: photos(in: url).count,
                    pickedCount: photos(in: selectionFolder(for: url)).count
                )
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    /// Image files directly inside `folder` (no recursion — `_auswahl` is a
    /// sub-folder and must stay invisible), sorted by file name.
    public static func photos(in folder: URL) -> [URL] {
        FolderScanner.scan(folder, recursive: false)
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                    == .orderedAscending
            }
    }

    public static func selectionFolder(for folder: URL) -> URL {
        folder.appendingPathComponent(selectionFolderName, isDirectory: true)
    }
}
