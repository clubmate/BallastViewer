import AppKit
import BallastCore
import SwiftUI

/// Captures the next key press app-wide via a local monitor. Only one session
/// can be live — starting another cancels the first (spec §9.9: recording stops
/// when focus moves on). While recording, `ShortcutMonitor` stands down so the
/// captured key never also fires as a shortcut.
@MainActor @Observable
final class KeyCaptureSession {
    private static weak var active: KeyCaptureSession?

    private(set) var isRecording = false
    @ObservationIgnored private var monitor: Any?

    func begin(onCapture: @escaping @MainActor (KeyChord) -> Void) {
        Self.active?.end()
        Self.active = self
        isRecording = true
        ShortcutMonitor.recorderActive = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let box = EventBox(event: event)
            MainActor.assumeIsolated {
                guard let self else { return }
                if let chord = KeyChord(event: box.event) {
                    self.end()
                    onCapture(chord)
                }
                // Unrepresentable presses (function keys …) keep recording.
            }
            return nil  // consumed — a recorded key must not reach anything else
        }
    }

    private struct EventBox: @unchecked Sendable {
        let event: NSEvent
    }

    func cancel() {
        end()
    }

    private func end() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        ShortcutMonitor.recorderActive = false
        if Self.active === self { Self.active = nil }
    }
}

/// The 80×20 monospaced key recorder (spec §9.9): shows the binding uppercased
/// or `None`; click → `Press…` on an accent background, the next key press is
/// captured and handed to `onRecord`.
struct KeyRecorderView: View {
    let chord: KeyChord?
    let onRecord: (KeyChord) -> Void

    @State private var session = KeyCaptureSession()

    var body: some View {
        Button {
            if session.isRecording {
                session.cancel()
            } else {
                session.begin { onRecord($0) }
            }
        } label: {
            Text(session.isRecording ? "Press…" : (chord?.keyString.uppercased() ?? "None"))
                .font(.caption.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 80, height: 20)
                .background(
                    session.isRecording
                        ? Color.accentColor.opacity(0.4)
                        : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.separator, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { session.cancel() }
    }
}
