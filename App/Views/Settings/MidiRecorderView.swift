import AppKit
import BallastCore
import SwiftUI

/// The 80×20 MIDI recorder (spec §9.9/§13.8): shows `CH<n> N:<note>` or
/// `None`; click → `MIDI…` on orange, the next incoming note is captured.
/// Pressing Return while armed clears the binding instead.
struct MidiRecorderView: View {
    let address: MidiAddress?
    let onRecord: (MidiAddress) -> Void
    let onClear: () -> Void

    @Environment(MidiService.self) private var midi
    @State private var isRecording = false
    @State private var returnMonitor: Any?

    var body: some View {
        Button {
            isRecording ? disarm() : arm()
        } label: {
            Text(isRecording ? "MIDI…" : (address?.displayName ?? "None"))
                .font(.caption.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 80, height: 20)
                .background(
                    isRecording
                        ? Color.orange.opacity(0.5)
                        : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.separator, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { disarm() }
    }

    private func arm() {
        isRecording = true
        midi.captureHandler = { captured in
            disarm()
            onRecord(captured)
        }
        // Return while armed clears the binding (§13.8).
        returnMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isReturn = event.keyCode == 36
            MainActor.assumeIsolated {
                if isReturn {
                    disarm()
                    onClear()
                }
            }
            return isReturn ? nil : event
        }
    }

    private func disarm() {
        isRecording = false
        midi.captureHandler = nil
        if let returnMonitor {
            NSEvent.removeMonitor(returnMonitor)
        }
        returnMonitor = nil
    }
}
