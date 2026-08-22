import SwiftUI

/// Window ▸ Photo Picker — opens the standalone selection utility.
struct PhotoPickerCommands: Commands {
    var body: some Commands {
        CommandGroup(before: .windowList) {
            OpenPhotoPickerButton()
            Divider()
        }
    }
}

private struct OpenPhotoPickerButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Photo Picker") { openWindow(id: "photoPicker") }
            .keyboardShortcut("p", modifiers: [.command, .shift])
    }
}
