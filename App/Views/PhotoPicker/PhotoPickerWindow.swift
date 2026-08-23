import AppKit
import BallastCore
import SwiftUI

/// The BallastPicker utility window: folder list left (photos waiting, picks
/// in `_auswahl` highlighted; collapsed via a grab-handle at its edge),
/// current photo right. The root is chosen once per window session (reopen
/// the picker to change it). Keys: ← → step, Space rotate, Return move to
/// `_auswahl`, Backspace undo the last pick. Full screen is the native one
/// (green button / ⌃⌘F); the title bar hides there like in any other app.
struct PhotoPickerWindow: View {
    @Bindable var model: PhotoPickerModel
    @State private var showFolders = true

    private let panelWidth: CGFloat = 260

    var body: some View {
        HStack(spacing: 0) {
            if showFolders {
                folderList
                    .frame(width: panelWidth)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .transition(.move(edge: .leading))
            }
            photoPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .leading) {
            panelHandle
                .offset(x: showFolders ? panelWidth - 10 : 0)
        }
        // U16 guard notice: inline, non-blocking — the user just picks
        // another folder.
        .overlay(alignment: .top) {
            if let notice = model.blockedMessage {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 12)
                    .padding(.leading, showFolders ? panelWidth : 0)
                    .transition(.opacity)
            }
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
        .alert(
            "BallastPicker",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            actions: { Button("OK") { model.errorMessage = nil } },
            message: { Text(model.errorMessage ?? "") }
        )
    }

    /// Small grab-handle at the panel edge: collapses the folder list, and
    /// stays at the window's left edge to bring it back.
    private var panelHandle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { showFolders.toggle() }
        } label: {
            Image(systemName: showFolders ? "chevron.left" : "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(showFolders ? "Hide Folders" : "Show Folders")
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
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var photoPane: some View {
        ZStack {
            Color.black
            // Failure first: a broken file must show the indicator, not the
            // previous photo's still-cached image.
            if model.decodeFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
            } else if let box = model.currentImage, model.currentPhoto != nil {
                SingleImageSurface(image: box.image, orientation: model.currentOrientation)
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
