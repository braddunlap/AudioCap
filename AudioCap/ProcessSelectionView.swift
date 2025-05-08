import SwiftUI
import AudioToolbox

@MainActor
struct ProcessSelectionView: View {
    @State private var processController = AudioProcessController()
    @State private var tap: ProcessTap?
    @State private var recorder: ProcessTapRecorder?

    @State private var selectedProcess: AudioProcess?
    enum CaptureMode: String, CaseIterable, Identifiable {
        case process = "Specific Process"
        case system = "System Audio Output"
        var id: String { self.rawValue }
    }
    @State private var captureMode: CaptureMode = .process

    var body: some View {
        Section {
            Picker("Capture Mode", selection: $captureMode) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: captureMode) { _, newMode in
                selectedProcess = nil
                teardownTapAndRecorder()
                
                if newMode == .system {
                    setupSystemOutputAudioRecording()
                }
            }

            if captureMode == .process {
                Picker("Process", selection: $selectedProcess) {
                    Text("Select…").tag(Optional<AudioProcess>.none)
                    ForEach(processController.processGroups) { group in
                        Section {
                            ForEach(group.processes) { process in
                                HStack {
                                    Image(nsImage: process.icon).resizable().aspectRatio(contentMode: .fit).frame(width: 16, height: 16)
                                    Text(process.name)
                                }.tag(Optional<AudioProcess>.some(process))
                            }
                        } header: { Text(group.title) }
                    }
                }
                .disabled(recorder?.isRecording == true)
                .onChange(of: selectedProcess) { oldValue, newValue in
                    guard newValue != oldValue else { return }
                    if let newProcess = newValue {
                        setupProcessRecording(for: newProcess)
                    } else {
                        teardownTapAndRecorder()
                    }
                }
            }
            
        } header: {
            Text("Source").font(.headline)
        }
        .task { processController.activate() }

        if let currentTap = tap {
            if let errorMessage = currentTap.errorMessage {
                Text("Error: \(errorMessage)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            } else if let currentRecorder = recorder {
                RecordingView(recorder: currentRecorder)
            } else if captureMode == .system && currentTap.activated {
                 Text("System audio output tap active. Ready to record.")
            }
        } else if captureMode == .system {
            Text("System Audio Output mode selected. Tap will be set up.")
        } else if captureMode == .process && selectedProcess == nil {
            Text("Please select a process to record.")
        }

    }

    private func setupProcessRecording(for process: AudioProcess) {
        teardownTapAndRecorder()
        let newTap = ProcessTap(process: process)
        self.tap = newTap
        createProcessRecorder()
        Task {
            do {
                try recorder?.start()
            } catch {
                print("ProcessSelectionView: Failed to start process recording for \(process.name): \(error.localizedDescription)")
                // Error should be on tap.errorMessage if activation failed
            }
        }
    }

    private func setupSystemOutputAudioRecording() {
        teardownTapAndRecorder()
        print("ProcessSelectionView: Setting up system audio output recording...")
        let newTap = ProcessTap(process: nil)
        self.tap = newTap
        createSystemOutputRecorder()
        Task {
            do {
                try recorder?.start()
            } catch {
                print("ProcessSelectionView: Failed to start system audio output recording: \(error.localizedDescription)")
                // Error should be on tap.errorMessage if activation failed
            }
        }
    }

    private func createProcessRecorder() {
        guard let currentTap = self.tap else {
            print("CreateProcessRecorder: Tap is nil, cannot create process recorder.")
            return
        }
        let filename = "\(currentTap.displayName)-\(Int(Date.now.timeIntervalSinceReferenceDate))"
        let audioFileURL = URL.applicationSupport.appendingPathComponent(filename, conformingTo: .wav)
        let newRecorder = ProcessTapRecorder(fileURL: audioFileURL, tap: currentTap)
        self.recorder = newRecorder
    }
    
    private func createSystemOutputRecorder() {
       print("ProcessSelectionView: Creating system output recorder...")
       guard let systemTap = self.tap else {
           print("CreateSystemOutputRecorder: System tap is nil.")
           return
       }
       let filename = "\(systemTap.displayName)-\(Int(Date.now.timeIntervalSinceReferenceDate))"
       let audioFileURL = URL.applicationSupport.appendingPathComponent(filename, conformingTo: .wav)
       let newRecorder = ProcessTapRecorder(fileURL: audioFileURL, tap: systemTap)
       self.recorder = newRecorder
    }

    private func teardownTapAndRecorder() {
        recorder?.stop()
        tap?.invalidate()
        self.tap = nil
        self.recorder = nil
    }
}

extension URL {
    static var applicationSupport: URL {
        do {
            let appSupport = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let subdir = appSupport.appending(path: "AudioCap", directoryHint: .isDirectory)
            if !FileManager.default.fileExists(atPath: subdir.path) {
                try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
            }
            return subdir
        } catch {
            assertionFailure("Failed to get application support directory: \(error)")
            return FileManager.default.temporaryDirectory
        }
    }
}
