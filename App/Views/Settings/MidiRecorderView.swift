import AppKit
import BallastCore
import SwiftUI

/// Owns one armed MIDI capture. Mirrors `KeyCaptureSession`: only one session
/// can be live — arming another disarms the first, so a stale recorder can
/// never keep the shared `captureHandler` or its Return monitor and clear the
/// wrong binding.
@MainActor @Observable
final class MidiCaptureSession {
    private static weak var active: MidiCaptureSession?

    private(set) var isRecording = false
    @ObservationIgnored private weak var midi: MidiService?
    @ObservationIgnored private var returnMonitor: Any?

    func begin(
        midi: MidiService,
        onRecord: @escaping @MainActor (MidiAddress) -> Void,
        onClear: @escaping @MainActor () -> Void
    ) {
        Self.active?.end()
        Self.active = self
        self.midi = midi
        isRecording = true
        midi.captureHandler = { [weak self] captured in
            self?.end()
            onRecord(captured)
        }
        // Return while armed clears the binding (§13.8).
        returnMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isReturn = event.keyCode == 36
            MainActor.assumeIsolated {
                if isReturn {
                    self?.end()
                    onClear()
                }
            }
            return isReturn ? nil : event
        }
    }

    func cancel() {
        end()
    }

    private func end() {
        isRecording = false
        if Self.active === self {
            // Only the live session may drop the shared handler — a session
            // that was superseded must not tear down its successor's capture.
            midi?.captureHandler = nil
            Self.active = nil
        }
        if let returnMonitor { NSEvent.removeMonitor(returnMonitor) }
        returnMonitor = nil
    }
}

/// The 80×20 MIDI recorder (spec §9.9/§13.8): shows `CH<n> N:<note>` or
/// `None`; click → `MIDI…` on orange, the next incoming note is captured.
/// Pressing Return while armed clears the binding instead.
struct MidiRecorderView: View {
    let address: MidiAddress?
    let onRecord: (MidiAddress) -> Void
    let onClear: () -> Void

    @Environment(MidiService.self) private var midi
    @State private var session = MidiCaptureSession()

    var body: some View {
        Button {
            if session.isRecording {
                session.cancel()
            } else {
                session.begin(midi: midi, onRecord: { onRecord($0) }, onClear: { onClear() })
            }
        } label: {
            RecorderPill(
                text: session.isRecording ? "MIDI…" : (address?.displayName ?? "None"),
                isActive: session.isRecording,
                activeColor: Color.orange.opacity(0.5)
            )
        }
        .buttonStyle(.plain)
        .onDisappear { session.cancel() }
    }
}
