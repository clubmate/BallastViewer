import SwiftUI

/// The 80×20 monospaced chip shared by the key and MIDI recorders; only the
/// recording tint differs between the two.
struct RecorderPill: View {
    let text: String
    let isActive: Bool
    let activeColor: Color

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 80, height: 20)
            .background(
                isActive ? activeColor : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.separator, lineWidth: 1)
            )
    }
}
