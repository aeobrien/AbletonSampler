import Foundation
import AVFoundation
import AudioKit
// import AudioKitUI // Uncomment if Fader is not found, though it should be in AudioKit

// Structure to hold device information for the UI
struct AudioDeviceInfo: Identifiable, Hashable {
    var id: AudioDeviceID // CoreAudio device ID
    var name: String
    var hasInput: Bool
    var deviceRef: Device // Keep a reference to the actual AudioKit Device
}

// ObservableObject to manage audio recording state and logic using AudioKit
class AudioRecorderManager: NSObject, ObservableObject {

    @Published var availableInputDevices: [AudioDeviceInfo] = []
    @Published var selectedDeviceID: AudioDeviceID? = nil { // Store the CoreAudio DeviceID
        didSet {
            // Find the actual Device object corresponding to the ID
            self.currentDevice = devices.first { $0.deviceID == selectedDeviceID }
            let deviceName = self.currentDevice?.name ?? "Not Found"
            print("Selected device ID changed to: \\(selectedDeviceID ?? 0). Corresponding device: \\(deviceName)")

            // Stop engine and clear nodes before setting up new ones
            if engine.avEngine.isRunning {
                engine.stop()
            }
            clearAudioKitNodes()

            updateChannelInfo(for: self.currentDevice)

            // Reset channel selection if device changes
            if oldValue != selectedDeviceID {
                 selectedChannelIndex = nil
            }

            // Automatically try to set up engine with new device if not recording
            if !isRecording && self.currentDevice != nil {
                 // Ensure permissions before setup
                 checkAndSetupEngine()
            }
        }
    }
    @Published var availableChannelIndices: [Int] = [] // Holds indices [0, 1, ...]
    @Published var selectedChannelIndex: Int? = nil { // Simple channel index selection
         didSet {
             print("Selected channel index changed to: \\(selectedChannelIndex ?? -1)")
         }
     }
    @Published var isRecording = false
    @Published var recordingError: String? = nil
    @Published var lastRecordedFileURL: URL? = nil

    let engine = AudioEngine()
    private var devices: [Device] = [] // Internal list of available AudioKit Device objects
    private var currentDevice: Device? = nil // The currently selected AudioKit Device object

    // AudioKit Nodes
    private var inputMixer: Mixer?
    private var recorder: NodeRecorder?
    private var silence: Mixer? // Using Mixer with volume 0 instead of Fader

    private var audioPlayer: AVAudioPlayer?
    @Published var isPlayingPreview = false

    // File management
    private var currentRecordingFileURL: URL?

    override init() {
        super.init()
        print("AudioRecorderManager Init (AudioKit v5+ macOS)")
        // No AVAudioSession setup needed for macOS
        // Device loading should be triggered after permission check
    }

    // Renamed from setupAudioKitEngine for clarity - checks permissions first
    private func checkAndSetupEngine() {
        requestMicrophoneAccess { [weak self] granted in
            guard let self = self else { return }
            if granted {
                if !self.setupAudioKitEngine() {
                    print("Engine setup failed after getting permission.")
                    // recordingError should be set by setupAudioKitEngine()
                }
            } else {
                print("Microphone permission denied, cannot setup engine.")
                self.recordingError = "Microphone access is required."
            }
        }
    }

    func loadInputDevices() {
        print("Loading input devices (AudioKit macOS)...")
        recordingError = nil
        DispatchQueue.main.async {
            // Use AudioKit's engine.inputDevices property to get devices the engine can use
            // Note: This might list devices that don't actually have input streams.
            // A more robust check might involve querying CoreAudio properties if needed,
            // but this is the standard AudioKit way to get settable input devices.
            // Corrected: Use the static member on the class, not the instance.
            self.devices = AudioEngine.inputDevices ?? [] 
            // self.devices = self.engine.inputDevices ?? [] // Incorrect: inputDevices is static
            // self.devices = Device.allDevices.filter { $0.isInput } // Incorrect API for engine device setting
            // self.devices = AudioEngine.availableInputDevices ?? [] // Incorrect API

            // Map to the struct used by the UI
            self.availableInputDevices
            = self.devices.map { device in
                return AudioDeviceInfo(id: device.deviceID,
                                       name: device.name,
                                       hasInput: (device.inputChannelCount ?? 0) > 0,
                                       deviceRef: device)
            }
            print("Found \\(self.availableInputDevices.count) input devices.")
            self.availableInputDevices.forEach { print("  - Name: \\($0.name), ID: \\($0.id)") }

            // Determine the device to select
            var deviceToSelect: AudioDeviceInfo? = nil

             // 1. Check if the currently selected device ID is still valid
            if let currentID = self.selectedDeviceID, let currentDevice = self.availableInputDevices.first(where: { $0.id == currentID }) {
                print("Previously selected device '\\(currentDevice.name)' is still available.")
                deviceToSelect = currentDevice
            }
             // 2. If no valid current selection, try the default input
            else if let defaultDevice = Device.defaultInputDevice(), let defaultDeviceInfo = self.availableInputDevices.first(where: { $0.id == defaultDevice.deviceID }) {
                 print("Selecting default input device: \\(defaultDeviceInfo.name)")
                 deviceToSelect = defaultDeviceInfo
             }
             // 3. Fallback to the first available device
            else if let firstDevice = self.availableInputDevices.first {
                 print("Selecting first available input device: \\(firstDevice.name)")
                 deviceToSelect = firstDevice
             }

            // Apply selection
            if let selected = deviceToSelect {
                 if self.selectedDeviceID != selected.id {
                     self.selectedDeviceID = selected.id // This triggers didSet
                 } else {
                     // If ID is the same, ensure currentDevice and channels are up-to-date
                     self.currentDevice = selected.deviceRef
                     self.updateChannelInfo(for: self.currentDevice)
                     // If engine was setup but nodes cleared maybe due to external change?
                     if !self.isRecording && self.currentDevice != nil && self.inputMixer == nil {
                        self.checkAndSetupEngine()
                     }
                 }
            } else {
                 print("No input devices available or could be selected.")
                 self.selectedDeviceID = nil // Triggers didSet
                 self.currentDevice = nil
                 self.availableChannelIndices = []
                 self.selectedChannelIndex = nil
            }
        }
    }

    // Update available channels based on the selected AudioKit Device (using CoreAudio)
    private func updateChannelInfo(for device: Device?) {
        guard let currentDeviceRef = device else {
            DispatchQueue.main.async {
                self.availableChannelIndices = []
                self.selectedChannelIndex = nil
            }
            return
        }

        // --- Using CoreAudio to query channel count ---
        print("Querying channel info for device: \\(currentDeviceRef.name) (ID: \\(currentDeviceRef.deviceID))")
        var channelCount: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var propsize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(currentDeviceRef.deviceID, &address, 0, nil, &propsize)

        if result == noErr && propsize > 0 {
             let bufferListPtr = malloc(Int(propsize))
             if bufferListPtr != nil {
                 result = AudioObjectGetPropertyData(currentDeviceRef.deviceID, &address, 0, nil, &propsize, bufferListPtr!)
                 if result == noErr {
                     let bufferList = bufferListPtr!.assumingMemoryBound(to: AudioBufferList.self).pointee
                     let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferListPtr!.assumingMemoryBound(to: AudioBufferList.self))!)
                     for i in 0..<Int(bufferList.mNumberBuffers) {
                         channelCount += buffers[i].mNumberChannels
                         print("  Buffer \\(i): \\(buffers[i].mNumberChannels) channels")
                     }
                      print("  -> Found \\(channelCount) input channels via CoreAudio query.")
                 } else {
                    print("  -> Error getting CoreAudio property data: \\(result)")
                 }
                 free(bufferListPtr)
             } else {
                 print("  -> Failed to allocate memory for CoreAudio property.")
             }
         } else {
             print("  -> Error getting CoreAudio property data size: \\(result) or size is 0.")
             channelCount = 0 // Report 0 if query fails
         }
         // --- End CoreAudio Query ---

        DispatchQueue.main.async {
            if channelCount > 0 {
                self.availableChannelIndices = Array(0..<Int(channelCount))
                if self.selectedChannelIndex == nil || !self.availableChannelIndices.contains(self.selectedChannelIndex!) {
                     self.selectedChannelIndex = self.availableChannelIndices.first
                 } else {
                    // Keep existing valid selection
                 }
                print("  -> Available channel indices: \\(self.availableChannelIndices), selected index: \\(self.selectedChannelIndex ?? -1)")
            } else {
                self.availableChannelIndices = []
                self.selectedChannelIndex = nil
                print("  -> No input channels found or error occurred querying channels.")
            }
        }
    }

    // Request microphone permission using standard AVFoundation method (macOS)
    func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("Microphone access already authorized.")
            // Don't load devices here, let the caller (e.g., onAppear or device selection) handle it
            completion(true)
        case .notDetermined:
            print("Requesting microphone access...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("Microphone access granted: \\(granted)")
                // Completion handler is on a background thread, dispatch if UI updates needed
                completion(granted)
            }
        case .denied, .restricted:
            print("Microphone access denied or restricted.")
            DispatchQueue.main.async {
                 self.recordingError = "Microphone access is required. Please grant access in System Settings > Privacy & Security."
                 completion(false)
             }
        @unknown default:
            print("Unknown microphone authorization status.")
            DispatchQueue.main.async {
                self.recordingError = "Could not determine microphone authorization status."
                completion(false)
            }
        }
    }

    // Sets up the AudioKit engine with the currently selected device
    private func setupAudioKitEngine() -> Bool {
        guard let device = currentDevice else {
            print("Engine Setup Error: No AudioKit device selected or initialized.")
            recordingError = "No input device selected."
            return false
        }

        // Note: Permission should have been checked by checkAndSetupEngine before calling this

        // Clear previous nodes if any exist
        clearAudioKitNodes() // Ensures clean state
        recordingError = nil

        print("Setting up AudioKit Engine for device: \\(device.name)")
        do {
            // 1. Set the device on the AudioKit Engine
            try engine.setDevice(device)
            print(" -> Input device set on AudioKit engine.")

            // 2. Create a mixer node connected to the engine's input
            guard let engineInput = engine.input else {
                print("Engine Setup Error: engine.input is nil after setting device.")
                recordingError = "Engine Setup Error: Failed to get engine input node."
                return false
            }
            inputMixer = Mixer(engineInput)
            print(" -> Input Mixer created and connected to engine input.")

            // 3. Set the engine's output (silenced using Mixer)
            silence = Mixer(inputMixer!)
            silence?.volume = 0
            engine.output = silence
            print(" -> Engine output set to silent Mixer (volume 0).")

            // Engine is ready, but not started yet.
            return true

        } catch {
            print("Error setting up AudioKit engine: \\(error)")
            // No AVFoundationErrorDomain check needed here
            if let nsError = error as NSError?, nsError.domain == NSOSStatusErrorDomain, nsError.code == kAudioUnitErr_FormatNotSupported {
                recordingError = "Engine Setup Error: Device format not supported."
            } else {
                 recordingError = "Engine Setup Error: \\(error.localizedDescription)"
            }
            clearAudioKitNodes() // Clean up on failure
            return false
        }
    }

    // Stops the engine and removes references to recorder/mixer nodes.
    internal func clearAudioKitNodes() {
         if engine.avEngine.isRunning {
            engine.stop()
            print("Engine stopped.")
         }
         recorder?.stop()
         recorder = nil

         inputMixer = nil
         silence = nil
         engine.output = nil

         print("Cleared AudioKit nodes (Recorder, Mixer, Silence Mixer). References set to nil.")
    }

    func startRecording() {
        // --- Pre-checks ---
        guard currentDevice != nil else {
            print("Record Error: No input device selected.")
            DispatchQueue.main.async { self.recordingError = "Please select an audio input device." }
            return
        }
        
        // Check permissions status synchronously before proceeding
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard authStatus == .authorized else {
            print("Record Error: Microphone access not authorized (" + String(describing: authStatus) + "). Requesting...")
            // Attempt to request. If denied, error will be set.
            // If undetermined, this call will trigger the request.
            // The user needs to interact with the system dialog THEN click record again.
            requestMicrophoneAccess { granted in
                if !granted {
                    DispatchQueue.main.async { self.recordingError = "Microphone access is required to record." }
                } else {
                     // Permission granted now, but user needs to initiate recording again.
                     print("Permission granted. Please start recording again.")
                     DispatchQueue.main.async { self.recordingError = "Microphone ready. Please start recording again." }
                }
            }
            return
        }

        // Check if engine needs setup (e.g., first run or after device change)
        if inputMixer == nil || engine.output == nil {
             print("Engine not fully setup, attempting setup now...")
             // setupAudioKitEngine assumes permissions are okay now
             if !setupAudioKitEngine() {
                 print("Record Error: Engine setup failed.")
                 // recordingError should be set by setupAudioKitEngine()
                 return
             }
         }

        // Channel selection check
        if !availableChannelIndices.isEmpty && selectedChannelIndex == nil {
            print("Record Error: Please select an input channel.")
            DispatchQueue.main.async { self.recordingError = "Please select an input channel." }
            return
        }

        guard let mixerNode = inputMixer else {
            print("Record Error: Input mixer node is missing.")
            DispatchQueue.main.async { self.recordingError = "Internal Error: Audio Mixer not ready." }
            return
        }

        // --- Setup Recorder ---
        recordingError = nil
        lastRecordedFileURL = nil
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Int(Date().timeIntervalSince1970)
        currentRecordingFileURL = documentsPath.appendingPathComponent("recording-\(timestamp).caf")
        guard let fileURL = currentRecordingFileURL else {
             print("Record Error: Failed to create file URL.")
             recordingError = "Failed to create recording file path."
             return
        }
        print("Recording to file: \\(fileURL.path)")

        recorder = NodeRecorder(node: mixerNode)
        print("NodeRecorder initialized for mixer node.")

        // --- Start Engine --- 
        // Separate do-catch for starting the engine
        if !engine.avEngine.isRunning {
            do {
                try engine.start() 
                print("Audio Engine started.")
            } catch let error as NSError {
                print("Error starting Audio Engine: \(error.localizedDescription)")
                print("Engine Start Error details: Domain=\(error.domain), Code=\(error.code), UserInfo=\(error.userInfo)")
                // Set error state and return, cannot proceed without engine
                DispatchQueue.main.async {
                     self.recordingError = "Error starting audio engine: \(error.localizedDescription)"
                     self.isRecording = false // Ensure recording state is false
                 }
                 // Clean up recorder instance if created before engine start failed
                 self.recorder = nil 
                 self.currentRecordingFileURL = nil
                 return // Exit startRecording
            }
        }
        
        // --- Start Recorder --- 
        // Separate do-catch for starting the recorder
        do {
            // Ensure recorder is not nil before trying to record
            guard let recorder = self.recorder else {
                print("Internal Error: Recorder became nil before recording could start.")
                DispatchQueue.main.async { self.recordingError = "Internal Recording Error." }
                return
            }
            // Now use the non-optional recorder instance
            try recorder.record(to: fileURL)
            print("NodeRecorder started recording to \(fileURL.lastPathComponent).")

            // Update state only after successful recording start
            DispatchQueue.main.async {
                self.isRecording = true
                print("Recording Started State Updated.")
            }
        } catch let error as NSError { // Catch errors specifically from recorder.record()
             print("Error starting NodeRecorder recording: \(error.localizedDescription)")
             print("Recorder Start Error details: Domain=\(error.domain), Code=\(error.code), UserInfo=\(error.userInfo)")
             if error.domain == NSOSStatusErrorDomain {
                 if error.code == kAudioFilePermissionsError {
                     recordingError = "Recording Error: Check file permissions or path."
                 } else if error.code == kAudioFileInvalidFileError {
                     recordingError = "Recording Error: Invalid audio file format/settings."
                 } else {
                     recordingError = "Recording Error (OSStatus \(error.code)): \(error.localizedDescription)"
                 }
             } else {
                 recordingError = "Recording Error: \(error.localizedDescription)"
             }
    
             // Clean up on failure
             self.recorder?.stop() // Stop if it somehow partially started
             self.recorder = nil
             self.currentRecordingFileURL = nil
             // Don't stop the engine here, it might be needed for other things
             DispatchQueue.main.async {
                 self.isRecording = false
             }
        }
    }

    func stopRecording() {
        print("Stopping recording...")
        guard isRecording, let recorder = recorder else {
            print("Not recording or recorder not initialized.")
            if isRecording {
                DispatchQueue.main.async { self.isRecording = false }
            }
            return
        }

        let recordedURL = self.currentRecordingFileURL

        recorder.stop()
        print("NodeRecorder stopped.")

        if engine.avEngine.isRunning {
            // Keep engine running for potential immediate playback
            print("Audio Engine remains running.")
        }

        DispatchQueue.main.async {
            self.isRecording = false
            self.lastRecordedFileURL = recordedURL // Set the last recorded URL *after* stopping
            // Corrected nil-coalescing operator to use a proper string literal "None"
            print("Recording Stopped State Updated. Last file: \(recordedURL?.lastPathComponent ?? "None")") 
            // Potential further actions after stopping could go here
        }
    }

    // MARK: - Playback Preview -

    func playPreview() {
        guard let url = lastRecordedFileURL else {
            print("Play Preview Error: No recorded file URL available.")
            return
        }
        print("Attempting to play preview of: \\(url.path)")

        // Use AVAudioPlayer for simple playback (macOS compatible)
        do {
            if audioPlayer?.isPlaying ?? false {
                stopPreview()
            }

            // No session activation needed on macOS
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            if audioPlayer?.play() == true {
                DispatchQueue.main.async {
                    self.isPlayingPreview = true
                    print("Playback started.")
                }
            } else {
                 print("Playback Error: AVAudioPlayer.play() returned false.")
                 DispatchQueue.main.async {
                      self.recordingError = "Playback Error: Failed to start playback."
                      self.isPlayingPreview = false
                      self.audioPlayer = nil
                  }
            }
        } catch {
            print("Error initializing or playing audio player: \\(error)")
            DispatchQueue.main.async {
                 self.recordingError = "Playback Error: \\(error.localizedDescription)"
                 self.isPlayingPreview = false
                 self.audioPlayer = nil
             }
        }
    }

    func stopPreview() {
        guard isPlayingPreview, let player = audioPlayer else {
            print("Not playing preview or player not initialized.")
            return
        }
        player.stop()
        print("Playback stopped by user.")
        DispatchQueue.main.async {
            self.isPlayingPreview = false
        }
         self.audioPlayer = nil
    }
}

// MARK: - AVAudioPlayerDelegate -
extension AudioRecorderManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("Playback finished. Success: \\(flag)")
        DispatchQueue.main.async {
            self.isPlayingPreview = false
        }
        self.audioPlayer = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let errorDesc = error?.localizedDescription ?? "Unknown error"
        print("Audio player decode error: \\(errorDesc)")
        DispatchQueue.main.async {
            self.recordingError = "Playback Decode Error: \\(errorDesc)"
            self.isPlayingPreview = false
        }
        self.audioPlayer = nil
    }
}

// MARK: - Helper to get Device by ID (Removed - Use PortDescription/UniqueID now)
// Corrected comment syntax or remove if unused
// // /* ... */ 
// Example of a correct multi-line comment if needed:
/*
 Helper function documentation if it existed.
*/
// Or just remove the line entirely if it's just placeholder junk.
