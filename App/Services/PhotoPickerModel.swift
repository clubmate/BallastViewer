import AppKit
import BallastCore
import ImageIO

/// State of the BallastPicker utility window — a first-pass selection tool
/// for freshly developed scans. Deliberately decoupled from the library: no
/// database, no catalog, no key map, no MIDI. It works straight on the file
/// system: folders inside a chosen root, one photo at a time, Enter moves the
/// file into `_auswahl`, Space rotates (metadata-only, lossless).
@MainActor
@Observable
final class PhotoPickerModel {
    private(set) var rootURL: URL?
    private(set) var folders: [PickerFolder] = []
    var selectedFolderID: PickerFolder.ID? {
        didSet { if selectedFolderID != oldValue { loadSelectedFolder() } }
    }
    private(set) var photos: [URL] = []
    private(set) var index = 0
    private(set) var currentImage: CGImageBox?
    private(set) var currentOrientation = 1
    private(set) var decodeFailed = false
    var errorMessage: String?

    /// The window whose key events drive the picker (registered by the view),
    /// mirroring the ShortcutMonitor whitelist pattern for the main window.
    weak var window: NSWindow?

    private var orientations: [String: Int] = [:]
    private var imageCache: [String: CGImageBox] = [:]
    private var cacheOrder: [String] = []
    private var decodeGeneration = 0
    /// Undo stack of picks: (original location, location inside _auswahl).
    private var picks: [(from: URL, to: URL)] = []
    private var monitor: Any?

    var currentPhoto: URL? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    var selectedFolder: PickerFolder? {
        folders.first { $0.id == selectedFolderID }
    }

    var canUndo: Bool { !picks.isEmpty }

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let box = EventBox(event: event)
            let consumed = MainActor.assumeIsolated {
                self?.consume(box.event) ?? false
            }
            return consumed ? nil : event
        }
    }

    private struct EventBox: @unchecked Sendable {
        let event: NSEvent
    }

    // MARK: Root & folders

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder that contains the photo folders."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setRoot(url)
    }

    func setRoot(_ url: URL) {
        rootURL = url
        picks.removeAll()
        folders = PhotoPickerScanner.folders(in: url)
        selectedFolderID = folders.first?.id
    }

    private func loadSelectedFolder() {
        imageCache.removeAll()
        cacheOrder.removeAll()
        orientations.removeAll()
        guard let folder = selectedFolder else {
            photos = []
            index = 0
            currentImage = nil
            return
        }
        photos = PhotoPickerScanner.photos(in: folder.url)
        index = 0
        showCurrent()
    }

    // MARK: Navigation

    func step(_ delta: Int) {
        guard !photos.isEmpty else { return }
        let next = min(max(index + delta, 0), photos.count - 1)
        guard next != index else { return }
        index = next
        showCurrent()
    }

    private func showCurrent() {
        decodeGeneration += 1
        let generation = decodeGeneration
        guard let url = currentPhoto else {
            currentImage = nil
            currentOrientation = 1
            decodeFailed = false
            return
        }
        currentOrientation = orientation(of: url)
        decodeFailed = false
        if let hit = imageCache[url.path] {
            currentImage = hit
        } else {
            Task {
                let box = await Self.decode(url)
                guard generation == self.decodeGeneration else { return }
                if let box { self.remember(box, for: url) }
                self.currentImage = box ?? self.currentImage
                self.decodeFailed = box == nil
            }
        }
        prefetchNeighbours()
    }

    private func prefetchNeighbours() {
        for offset in [1, -1, 2] {
            let i = index + offset
            guard photos.indices.contains(i) else { continue }
            let url = photos[i]
            guard imageCache[url.path] == nil else { continue }
            Task {
                guard let box = await Self.decode(url) else { return }
                self.remember(box, for: url)
            }
        }
    }

    private func remember(_ box: CGImageBox, for url: URL) {
        guard imageCache[url.path] == nil else { return }
        imageCache[url.path] = box
        cacheOrder.append(url.path)
        while cacheOrder.count > 8 {
            imageCache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    /// Q5 convention: decoded without the EXIF transform; rotation is applied
    /// by the view layer from the stored orientation.
    nonisolated private static func decode(_ url: URL) async -> CGImageBox? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              )
        else { return nil }
        return CGImageBox(image: image)
    }

    private func orientation(of url: URL) -> Int {
        if let known = orientations[url.path] { return known }
        let value = MetadataReader.readIfReadable(from: url)?.orientation ?? 1
        orientations[url.path] = value
        return value
    }

    // MARK: Actions

    /// Space: advance the EXIF cycle in memory (instant), then persist it into
    /// the file's metadata — image bytes untouched.
    func rotate() {
        guard let url = currentPhoto else { return }
        let next = RotationCycle.next(after: currentOrientation)
        currentOrientation = next
        orientations[url.path] = next
        Task.detached {
            do {
                try MetadataWriter.writeOrientation(next, to: url)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not save rotation for \(url.lastPathComponent): \(error)"
                }
            }
        }
    }

    /// Enter: move the current file into `_auswahl` next to it and show the
    /// next photo.
    func pick() {
        guard let url = currentPhoto, let folder = selectedFolder else { return }
        let target = PhotoPickerScanner.selectionFolder(for: folder.url)
        let destination = target.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                errorMessage = "\(url.lastPathComponent) already exists in \(PhotoPickerScanner.selectionFolderName)."
                return
            }
            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            errorMessage = "Could not move \(url.lastPathComponent): \(error.localizedDescription)"
            return
        }
        picks.append((from: url, to: destination))
        photos.remove(at: index)
        imageCache.removeValue(forKey: url.path)
        adjustCounts(for: folder.id, photos: -1, picked: 1)
        if index >= photos.count { index = max(photos.count - 1, 0) }
        showCurrent()
    }

    /// Backspace: move the most recently picked file back and show it again.
    func undoPick() {
        guard let last = picks.popLast() else { return }
        do {
            try FileManager.default.moveItem(at: last.to, to: last.from)
        } catch {
            errorMessage = "Could not move \(last.from.lastPathComponent) back: \(error.localizedDescription)"
            return
        }
        let folderURL = last.from.deletingLastPathComponent()
        adjustCounts(for: folderURL.path, photos: 1, picked: -1)
        if selectedFolder?.url.path == folderURL.path {
            let insertAt = photos.firstIndex {
                $0.lastPathComponent.localizedStandardCompare(last.from.lastPathComponent)
                    == .orderedDescending
            } ?? photos.count
            photos.insert(last.from, at: insertAt)
            index = insertAt
            showCurrent()
        } else {
            selectedFolderID = folderURL.path
            if let i = photos.firstIndex(where: { $0.path == last.from.path }) {
                index = i
                showCurrent()
            }
        }
    }

    private func adjustCounts(for folderID: PickerFolder.ID, photos: Int, picked: Int) {
        guard let i = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[i].photoCount += photos
        folders[i].pickedCount += picked
    }

    // MARK: Keys

    /// Fixed picker shortcuts, only while the picker window is key and no
    /// sheet/text field has focus. Consumed events never reach the main
    /// window's menu key equivalents.
    private func consume(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, window.attachedSheet == nil,
              !(window.firstResponder is NSText)
        else { return false }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return false
        }
        switch event.keyCode {
        case 123: step(-1)          // ←
        case 124: step(1)           // →
        case 49: rotate()           // Space
        case 36, 76: pick()         // Return / Enter
        case 51: undoPick()         // Backspace
        default: return false
        }
        return true
    }
}
