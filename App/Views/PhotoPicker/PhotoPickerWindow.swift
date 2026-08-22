import AppKit
import BallastCore
import SwiftUI

/// The Photo Picker utility window: folder list left (photos waiting, picks
/// in `_auswahl` highlighted; toggled via the toolbar), current photo right.
/// The root is chosen once per window session (restart the picker to change it). Keys: ← → step, Space
/// rotate, Return move to `_auswahl`, Backspace undo the last pick.
struct PhotoPickerWindow: View {
    @Bindable var model: PhotoPickerModel
    @State private var showFolders = true

    var body: some View {
        HSplitView {
            if showFolders {
                folderList
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 400)
            }
            photoPane
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 450)
        .background(PickerWindowRegistrar(model: model))
        .task {
            #if DEBUG
            // Headless check hook: pre-select a root so the picker can be
            // exercised without the (sandbox-only) open panel.
            if model.rootURL == nil,
               let path = ProcessInfo.processInfo.environment["BV_TEST_PICKER_ROOT"] {
                model.setRoot(URL(fileURLWithPath: path, isDirectory: true))
            }
            #endif
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showFolders.toggle() }
                } label: {
                    Label(showFolders ? "Hide Folders" : "Show Folders", systemImage: "sidebar.left")
                }
                .help(showFolders ? "Hide Folders" : "Show Folders")
            }
            ToolbarItem {
                Button {
                    model.window?.toggleFullScreen(nil)
                } label: {
                    Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Enter Full Screen (⌃⌘F)")
            }
        }
        .alert(
            "Photo Picker",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            actions: { Button("OK") { model.errorMessage = nil } },
            message: { Text(model.errorMessage ?? "") }
        )
    }

    @ViewBuilder
    private var folderList: some View {
        if model.rootURL == nil {
            VStack(spacing: 12) {
                Text("No folder chosen")
                    .foregroundStyle(.secondary)
                Button("Choose Folder…") { model.chooseRoot() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.folders, selection: $model.selectedFolderID) { folder in
                HStack {
                    Text(folder.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(folder.photoCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if folder.pickedCount > 0 {
                        Text("\(folder.pickedCount)")
                            .monospacedDigit()
                            .foregroundStyle(.green)
                            .fontWeight(.semibold)
                    }
                }
                .tag(folder.id)
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var photoPane: some View {
        ZStack {
            Color.black
            if let box = model.currentImage, model.currentPhoto != nil {
                SingleImageSurface(image: box.image, orientation: model.currentOrientation)
            } else if model.decodeFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
            } else if model.currentPhoto == nil {
                Text(model.selectedFolder == nil ? "No Folder Selected" : "No Photos Left")
                    .font(.title)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
    }
}

/// Hands the hosting NSWindow to the picker model's key monitor whitelist.
private struct PickerWindowRegistrar: NSViewRepresentable {
    let model: PhotoPickerModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            model.window = view?.window
            view?.window?.collectionBehavior.insert(.fullScreenPrimary)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window, model.window !== window {
            DispatchQueue.main.async {
                model.window = window
                window.collectionBehavior.insert(.fullScreenPrimary)
            }
        }
    }
}
