import SwiftUI
import AudioToolbox
import OSLog
import AVFoundation

@Observable
final class ProcessTap {

    typealias InvalidationHandler = (ProcessTap) -> Void

    let process: AudioProcess?
    let muteWhenRunning: Bool
    private let logger: Logger

    private(set) var errorMessage: String? = nil

    init(process: AudioProcess?, muteWhenRunning: Bool = false) {
        self.process = process
        self.muteWhenRunning = muteWhenRunning
        let tapName = process?.name ?? "SystemAudioOutput"
        self.logger = Logger(subsystem: kAppSubsystem, category: "\(String(describing: ProcessTap.self))(\(tapName))")
    }

    @ObservationIgnored
    private var processTapID: AudioObjectID = .unknown
    @ObservationIgnored
    private var aggregateDeviceID = AudioObjectID.unknown
    @ObservationIgnored
    private var deviceProcID: AudioDeviceIOProcID?
    @ObservationIgnored
    private(set) var tapStreamDescription: AudioStreamBasicDescription?
    @ObservationIgnored
    private var invalidationHandler: InvalidationHandler?

    @ObservationIgnored
    private(set) var activated = false

    var displayName: String {
        process?.name ?? "System Audio Output"
    }

    @MainActor
    func activate() {
        guard !activated else { return }
        activated = true

        logger.debug(#function)
        self.errorMessage = nil

        do {
            try prepare(forProcessObjectID: self.process?.objectID)
        } catch {
            logger.error("\(error, privacy: .public)")
            self.errorMessage = error.localizedDescription
        }
    }

    func invalidate() {
        guard activated else { return }
        defer { activated = false }

        logger.debug(#function)

        invalidationHandler?(self)
        self.invalidationHandler = nil

        if aggregateDeviceID.isValid {
            var err = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if err != noErr { logger.warning("Failed to stop aggregate device: \(err, privacy: .public)") }

            if let deviceProcID {
                err = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                if err != noErr { logger.warning("Failed to destroy device I/O proc: \(err, privacy: .public)") }
                self.deviceProcID = nil
            }

            err = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if err != noErr {
                logger.warning("Failed to destroy aggregate device: \(err, privacy: .public)")
            }
            aggregateDeviceID = .unknown
        }

        if processTapID.isValid {
            let err = AudioHardwareDestroyProcessTap(processTapID)
            if err != noErr {
                logger.warning("Failed to destroy audio tap: \(err, privacy: .public)")
            }
            self.processTapID = .unknown
        }
    }

    private func prepare(forProcessObjectID processObjectID: AudioObjectID?) throws {
        errorMessage = nil

        let tapDescription: CATapDescription
        if let objectID = processObjectID {
            tapDescription = CATapDescription(stereoMixdownOfProcesses: [objectID])
            logger.debug("Configuring tap for process objectID: \(objectID)")
        } else {
            tapDescription = CATapDescription(stereoMixdownOfProcesses: [])
            logger.debug("Configuring tap for system audio output (all processes).")
        }
        
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = muteWhenRunning ? .mutedWhenTapped : .unmuted
        var tapID: AUAudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)

        guard err == noErr else {
            errorMessage = "Process/System tap creation failed with error \(err)"
            throw errorMessage ?? "Unknown error creating tap."
        }

        logger.debug("Created process/system tap #\(tapID, privacy: .public)")
        self.processTapID = tapID

        let allDeviceIDs = try AudioObjectID.system.getAllHardwareDevices()
        var outputUIDs: [String] = []
        var outputDeviceIDs: [AudioDeviceID] = []
        for devID in allDeviceIDs {
            do {
                let outputChans = try devID.getTotalOutputChannelCount()    
                if outputChans > 0 {
                    let devUID = try devID.readDeviceUID()
                    outputUIDs.append(devUID)
                    outputDeviceIDs.append(devID)
                }
            } catch {
                logger.warning("Ignored device \(devID): \(error.localizedDescription)")
            }
        }

        if outputUIDs.isEmpty {
            throw "No hardware output devices found!"
        }

        let systemOutputID = try AudioDeviceID.readDefaultSystemOutputDevice()
        let mainSubdeviceUID = try systemOutputID.readDeviceUID()

        let aggregateUID = UUID().uuidString
        let aggregateDeviceName = processObjectID != nil ? "Tap-\(self.displayName)" : "Tap-SystemOutput"

        let subDeviceList = outputUIDs.map { [kAudioSubDeviceUIDKey: $0] }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: aggregateDeviceName,
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: mainSubdeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: subDeviceList,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        self.tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()

        aggregateDeviceID = AudioObjectID.unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
        guard err == noErr else {
            throw "Failed to create aggregate device: \(err)"
        }

        logger.debug("Created aggregate device #\(self.aggregateDeviceID, privacy: .public)")
    }

    func run(on queue: DispatchQueue, ioBlock: @escaping AudioDeviceIOBlock, invalidationHandler: @escaping InvalidationHandler) throws {
        assert(activated, "\(#function) called with inactive tap!")
        assert(self.invalidationHandler == nil, "\(#function) called with tap already active!")

        errorMessage = nil
        logger.debug("Run tap!")
        self.invalidationHandler = invalidationHandler

        var err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue, ioBlock)
        guard err == noErr else { throw "Failed to create device I/O proc: \(err)" }

        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else { throw "Failed to start audio device: \(err)" }
    }

    deinit { invalidate() }

}

private extension AudioDeviceID {
    func getTotalOutputChannelCount() throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        if err == kAudioHardwareUnknownPropertyError || dataSize == 0 {
            return 0
        }
        guard err == noErr else {
            throw "Error reading data size for output stream configuration: \(err)"
        }
        let bufferListPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferListPtr.deallocate() }
        err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, bufferListPtr)
        guard err == noErr else {
            throw "Error reading output stream configuration: \(err)"
        }
        let audioBufferList = bufferListPtr.assumingMemoryBound(to: AudioBufferList.self)
        var totalOutputChannels: UInt32 = 0
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for i in 0..<Int(buffers.count) {
            totalOutputChannels += buffers[i].mNumberChannels
        }
        return totalOutputChannels
    }
}

@Observable
final class ProcessTapRecorder {

    let fileURL: URL
    let tapDisplayName: String
    let icon: NSImage

    private(set) var currentAudioLevel: Float = 0.0 

    private let queue = DispatchQueue(label: "ProcessTapRecorder", qos: .userInitiated)
    private let logger: Logger

    @ObservationIgnored
    private weak var _tap: ProcessTap?

    private(set) var isRecording = false 

    init(fileURL: URL, tap: ProcessTap) {
        self.tapDisplayName = tap.displayName
        self.fileURL = fileURL
        self._tap = tap
        self.logger = Logger(subsystem: kAppSubsystem, category: "\(String(describing: ProcessTapRecorder.self))(\(fileURL.lastPathComponent))")
        
        if let process = tap.process {
            self.icon = process.icon
        } else {
            self.icon = NSWorkspace.shared.icon(for: .applicationBundle)
        }
    }

    private var tap: ProcessTap {
        get throws {
            guard let _tap else { throw "Process tap unavailable" }
            return _tap
        }
    }

    @ObservationIgnored
    private var currentFile: AVAudioFile?

    @MainActor 
    func start() throws {
        logger.debug(#function)
        
        guard !isRecording else {
            logger.warning("\(#function, privacy: .public) while already recording")
            return
        }

        self.isRecording = true 

        let tap = try tap

        if !tap.activated {
            tap.activate()
            if let errorMessage = tap.errorMessage {
                logger.error("Tap activation error: \(errorMessage)")
                self.isRecording = false 
                throw errorMessage
            }
        }

        guard var streamDescription = tap.tapStreamDescription else {
            logger.error("Tap stream description not available.")
            self.isRecording = false 
            throw "Tap stream description not available."
        }

        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            logger.error("Failed to create AVAudioFormat from stream description.")
            self.isRecording = false 
            throw "Failed to create AVAudioFormat."
        }

        logger.info("Using audio format: \(format, privacy: .public)")

        let settings: [String: Any] = [
            AVFormatIDKey: streamDescription.mFormatID,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount
        ]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        
        do {
            let file = try AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
            self.currentFile = file
        } catch {
            logger.error("Failed to create AVAudioFile for writing: \(error, privacy: .public)")
            self.isRecording = false 
            throw error
        }

        try tap.run(on: queue) { [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            guard let self else { return } 
            var localAudioLevel: Float = 0.0
            
            do {
                guard let currentFile = self.currentFile else { 
                    DispatchQueue.main.async { if self.currentAudioLevel != 0.0 { self.currentAudioLevel = 0.0 } }
                    return
                }
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil) else {
                    print("ProcessTapRecorder: Failed to create PCM buffer")
                    DispatchQueue.main.async { if self.currentAudioLevel != 0.0 { self.currentAudioLevel = 0.0 } }
                    return
                }
                
                var rms: Float = 0.0
                if let floatChannelData = buffer.floatChannelData, buffer.frameLength > 0 {
                    let channelData = floatChannelData[0]
                    let frameLength = Int(buffer.frameLength)
                    var sumOfSquares: Float = 0.0
                    for i in 0..<frameLength {
                        let sample = channelData[i]
                        sumOfSquares += sample * sample
                    }
                    rms = sqrt(sumOfSquares / Float(frameLength))
                }
                
                localAudioLevel = min(max(rms * 2.0, 0.0), 1.0)

                if buffer.frameLength == 0 {
                    print("ProcessTapRecorder: Warning - received zero frames!")
                }

                try currentFile.write(from: buffer)

            } catch {
                self.logger.error("Buffer write error: \(error, privacy: .public)")
                print("ProcessTapRecorder: Buffer write error:", error)
                localAudioLevel = 0.0 
            }
            
            DispatchQueue.main.async {
                self.currentAudioLevel = localAudioLevel
            }

        } invalidationHandler: { [weak self] tap in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handleInvalidation()
            }
        }
        print("ProcessTapRecorder: Recording started (isRecording set to true).")
    }

    @MainActor 
    func stop() {
        logger.debug(#function)
        guard isRecording else { return }
        
        self.currentAudioLevel = 0.0
        self.isRecording = false 

        guard let tapToInvalidate = try? self.tap else {
            logger.warning("Tap unavailable during stop. Cleaning up recorder state.")
            self.currentFile = nil
            return
        }
        
        tapToInvalidate.invalidate()
            
        self.currentFile = nil
    }

    @MainActor 
    private func handleInvalidation() {
        logger.debug("Handling tap invalidation in recorder.")
        if isRecording {
            logger.info("Tap invalidated while recording. Stopping recording.")
            self.currentFile = nil
            self.isRecording = false 
            self.currentAudioLevel = 0.0
        }
    }
}
