import SwiftUI
// import AVFoundation // Keep if needed for other AV types, remove if only for AVAudioSession
import CoreAudio // No longer needed
import AVFoundation // Needed for AVAudioPlayerDelegate via manager
import AudioKit // Import AudioKit
// import AudioKitUI // If AudioKitUI needs AudioKit itself
// import AudioKitUI // Import AudioKitUI for waveform view

struct AudioRecorderView: View {
    // Use StateObject to create and manage the recorder's lifecycle within this view
    @StateObject private var audioManager = AudioRecorderManager()

    // Access the main SamplerViewModel to add the sample
    @EnvironmentObject var viewModel: SamplerViewModel

    // State to know which key to assign the recorded sample to
    // TODO: Implement a way for the user to select this (e.g., a TextField or Picker)
    @State private var targetMIDIKey: Int = 60 // Default to C4

    // To dismiss the sheet
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            Text("Audio Recorder")
                .font(.largeTitle)
                .padding(.bottom)

            // --- Device Selection (Using AudioKit Device) ---
            // Bind selection to the ID, which is Observable
            Picker("Input Device", selection: $audioManager.selectedDeviceID) {
                // Optional tag for representing no selection
                Text("Select a Device").tag(nil as AudioDeviceID?)
                // Iterate over the AudioDeviceInfo struct array
                ForEach(audioManager.availableInputDevices, id: \.id) { deviceInfo in
                    // Display the name, tag with the ID (cast to optional to match selection type)
                    Text(deviceInfo.name).tag(deviceInfo.id as AudioDeviceID?)
                }
            }
            .padding(.bottom)
            .disabled(audioManager.isRecording) // Disable picker while recording

            // --- Channel Selection Picker (Uses indices from manager) ---
            if !audioManager.availableChannelIndices.isEmpty {
                Picker("Input Channel", selection: $audioManager.selectedChannelIndex) {
                     Text("Select Channel").tag(Int?.none)
                     ForEach(audioManager.availableChannelIndices, id: \.self) { index in
                         Text("Channel \(index + 1)").tag(index as Int?)
                     }
                 }
                 .padding(.bottom)
                 .disabled(audioManager.isRecording)
            }

            // --- Record Button ---
            Button {
                if audioManager.isRecording {
                    audioManager.stopRecording()
                } else {
                    audioManager.startRecording()
                }
            } label: {
                 Image(systemName: audioManager.isRecording ? "stop.circle.fill" : "record.circle.fill")
                     .resizable().aspectRatio(contentMode: .fit).frame(width: 50, height: 50)
                     .foregroundColor(audioManager.isRecording ? .red : .blue)
             }
            .padding()
             .disabled(
                 // Disable if no device ID is selected OR
                 // if channels are available but no channel index is selected
                 // (unless already recording, then allow stop)
                 (audioManager.selectedDeviceID == nil && !audioManager.isRecording) ||
                 (!audioManager.availableChannelIndices.isEmpty && audioManager.selectedChannelIndex == nil && !audioManager.isRecording)
              )

            // --- Status/Error Display ---
            if let errorMsg = audioManager.recordingError {
                Text("Error: \(errorMsg)")
                    .foregroundColor(.red).padding().frame(maxWidth: 350)
            } else if audioManager.isRecording {
                Text("Recording...")
                    .foregroundColor(.red).padding()
            } else if audioManager.lastRecordedFileURL != nil {
                 Text("Recording finished.")
                     .foregroundColor(.green).padding()
             }

            // --- Waveform & Playback Controls ---
            if let recordedURL = audioManager.lastRecordedFileURL, !audioManager.isRecording {
                VStack {
                    Divider().padding(.vertical)
                    Text("Preview").font(.headline)

                    // --- Waveform View (Still Commented Out) ---
                    // AudioWaveform(url: recordedURL) // <<< COMMENTED OUT - Requires different initializer (e.g., pre-calculated data)
                    //    .frame(height: 100)
                    //     .padding(.bottom)
                    //    .foregroundColor(.blue) // Example styling

                    // --- Playback Buttons ---
                    HStack(spacing: 20) {
                        Button {
                            if audioManager.isPlayingPreview {
                                audioManager.pausePreview()
                            } else {
                                audioManager.playPreview()
                            }
                        } label: {
                            Image(systemName: audioManager.isPlayingPreview ? "pause.fill" : "play.fill")
                                .font(.title)
                        }

                        Button {
                            audioManager.stopPreview()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.title)
                        }
                    }
                     .padding(.bottom)

                }
                .transition(.opacity.animation(.easeInOut))
            }

            // --- Target Key Selection ---
            HStack {
                 Text("Target MIDI Key:")
                 TextField("Key (0-127)", value: $targetMIDIKey, formatter: NumberFormatter())
                     .frame(width: 50).textFieldStyle(RoundedBorderTextFieldStyle())
                     .disabled(audioManager.isRecording)
             }
             .padding(.top)

            Spacer()

            // --- Button to Add Recorded Sample ---
             Button("Add Recording to Sampler") {
                 addRecordingToSampler()
             }
             .padding(.bottom)
             .disabled(audioManager.lastRecordedFileURL == nil || audioManager.isRecording || !isValidMIDIKey(targetMIDIKey))

        }
        .padding()
        .frame(minWidth: 450, minHeight: 450)
        .onChange(of: audioManager.lastRecordedFileURL) { newURL in
             if newURL != nil {
                 audioManager.stopPreview()
             }
        }
        .onAppear {
            // Use the manager's permission request which now calls loadInputDevices
            print("AudioRecorderView appeared. Requesting access.")
            audioManager.requestMicrophoneAccess { granted in
                   print("Microphone access granted in view onAppear: \(granted)")
                   // Devices are loaded within the manager if granted
            }
        }
        .onDisappear {
            // Stop playback and potentially engine/nodes
             print("AudioRecorderView disappearing.")
             audioManager.stopPreview()
             // Ensure engine is stopped and nodes cleared when view goes away
             audioManager.clearAudioKitNodes()
         }
    }

    // --- Helper to validate MIDI key ---
    private func isValidMIDIKey(_ key: Int) -> Bool {
        return key >= 0 && key <= 127
    }

    // --- Function to handle adding the recorded sample ---
     private func addRecordingToSampler() {
         guard let recordedURL = audioManager.lastRecordedFileURL else { return }
         guard isValidMIDIKey(targetMIDIKey) else { return }
         viewModel.addSample(from: recordedURL, for: targetMIDIKey)
         dismiss()
     }

}

// MARK: - Preview
struct AudioRecorderView_Previews: PreviewProvider {
    static var previews: some View {
        // Create dummy view model for preview
        let previewViewModel = SamplerViewModel()
        AudioRecorderView()
            .environmentObject(previewViewModel) // Provide the ViewModel for the preview
            // The AudioRecorderManager will be created within the view by @StateObject
            // Note: CoreAudio device selection and recording won't work fully in previews.
    }
} 