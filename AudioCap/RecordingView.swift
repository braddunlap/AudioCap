import SwiftUI

@MainActor
struct RecordingView: View {
    let recorder: ProcessTapRecorder

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
                RecordingIndicator(appIcon: recorder.icon, isRecording: recorder.isRecording)

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
