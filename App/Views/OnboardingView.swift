import SwiftUI

/// Empty state with direct actions instead of a menu treasure hunt (U1, fixes C13).
struct OnboardingView: View {
    @Environment(LibraryController.self) private var controller

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Welcome to ballastviewer")
                .font(.title)
            Text("A library catalogs your photos for fast culling and keywording.\nYour image files are never modified or moved.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Create Library…") { controller.presentNewLibraryPanel() }
                    .buttonStyle(.borderedProminent)
                Button("Open Library…") { controller.presentOpenLibraryPanel() }
            }
            .controlSize(.large)
            .padding(.top, 12)
            Text("Tip: drop a photo folder anywhere in this window to get started.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
