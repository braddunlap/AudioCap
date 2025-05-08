import SwiftUI

@MainActor
struct RecordingView: View {
    // If ProcessTapRecorder is @Observable, this should work fine with @State.
    // For older iOS/macOS, you might need @ObservedObject if it were an ObservableObject.
    // With @Observable, @State should re-render on changes to @Published properties.
    @State var recorder: ProcessTapRecorder 

    @State private var lastRecordingURL: URL?

    var body: some View {
        Section {
            HStack {
                if recorder.isRecording {
                    Button("Stop") {
                        // Ensure stop is called on the main actor if it updates main actor properties
                        recorder.stop()
                    }
                    .id("button")
                } else {
                    Button("Start") {
                        handlingErrors {
                            // Ensure start is called on the main actor
                            try recorder.start()
                        }
                    }
                    .id("button")

                    if let lastRecordingURL {
                        FileProxyView(url: lastRecordingURL)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .animation(.smooth, value: recorder.isRecording)
            .animation(.smooth, value: lastRecordingURL)
            .onChange(of: recorder.isRecording) { _, newValue in
                // recorder.fileURL might change if a new recording starts with a new file.
                // This logic seems fine.
                if !newValue { lastRecordingURL = recorder.fileURL }
            }
        } header: {
            HStack {
                // UPDATE: Pass the live audio level to the indicator
                RecordingIndicator(
                    appIcon: recorder.icon,
                    isRecording: recorder.isRecording,
                    audioLevel: recorder.currentAudioLevel // Pass the live audio level
                )

                Text(recorder.isRecording ? "Recording from \(recorder.tapDisplayName)" : "Ready to Record from \(recorder.tapDisplayName)")
                    .font(.headline)
                    .contentTransition(.identity)
            }
        }
    }

    private func handlingErrors(perform block: () throws -> Void) {
        do {
            try block()
        } catch {
            /// "handling" in the function name might not be entirely true
            NSAlert(error: error).runModal()
        }
    }
}
