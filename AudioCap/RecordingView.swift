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
                        recorder.stop()
                    }
                    .id("button")
                } else {
                    Button("Start") {
                        handlingErrors {
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
                if !newValue { lastRecordingURL = recorder.fileURL }
            }
        } header: {
            HStack {
                RecordingIndicator(
                    appIcon: recorder.icon,
                    isRecording: recorder.isRecording,
                    audioLevel: recorder.currentAudioLevel
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
