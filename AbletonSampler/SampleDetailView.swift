import SwiftUI
import AVFoundation // For audio file info
import AudioKit // For potential audio processing/waveform data
import AudioKitUI // For waveform view

// Placeholder for Waveform Drawing (Can refine later, potentially reuse/adapt from AudioSegmentEditorView)
struct SampleDetailWaveformView: View {
    let audioFileURL: URL
    let segmentStartSample: Int64
    let segmentEndSample: Int64
    let totalFrames: Int64 // Total frames of the source file

    // TODO: Implement waveform drawing logic showing the segment within the full waveform
    var body: some View {
        // Use GeometryReader to get available width on macOS
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background waveform (full file)
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 150)
                    .overlay(Text("Full Waveform Placeholder").foregroundColor(.secondary))

                // Highlighted Segment
                // Calculate position and width based on segment samples and total frames
                let totalWidth = geometry.size.width // Use geometry width
                let startRatio = totalFrames > 0 ? Double(segmentStartSample) / Double(totalFrames) : 0
                let endRatio = totalFrames > 0 ? Double(segmentEndSample) / Double(totalFrames) : 0
                let segmentWidth = max(1, totalWidth * (endRatio - startRatio)) // Ensure min width of 1
                let segmentXOffset = totalWidth * startRatio

                Rectangle()
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: segmentWidth, height: 150)
                    .offset(x: segmentXOffset)
                    .overlay(Text("Segment").foregroundColor(.white))

                // TODO: Add Start/End Markers visually if needed
            }
        } // End GeometryReader
        .frame(height: 150)
        .clipped() // Ensure segment doesn't draw outside bounds
        .padding(.horizontal)
    }
}


struct SampleDetailView: View {
    @EnvironmentObject var viewModel: SamplerViewModel

    let midiNote: Int
    let samples: [MultiSamplePartData]

    @State private var audioFileTotalFrames: Int64? = nil

    // --- NEW State for Picker Selection (Only used when count > 1) ---
    @State private var pickerSelectedSample: MultiSamplePartData? = nil
    // ----------------------------------------------------------------

    // Helper to get the sample to display (either the single one, or the picker selection)
    private var sampleToDisplay: MultiSamplePartData? {
        if samples.count == 1 {
            return samples.first
        } else {
            return pickerSelectedSample
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // --- Header Section --- 
            HStack {
                Text("Sample Details for Note \(midiNote) (\(viewModel.pianoKeys.first { $0.id == midiNote }?.name ?? "N/A"))")
                    .font(.title3)
                Spacer()
            }
            .padding(.bottom, 5)

            // --- Display "No Sample" Message --- 
            if samples.isEmpty {
                Text("No sample assigned to this key.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                Spacer()
            } else {
                // --- Sample Selector (Only if multiple samples exist) ---
                if samples.count > 1 {
                    Picker("Select Sample:", selection: $pickerSelectedSample) {
                        ForEach(samples) { sample in
                            Text("Sample (Vel: \(sample.velocityRange.min)-\(sample.velocityRange.max))")
                                .tag(sample as MultiSamplePartData?)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom)
                }

                // --- Details for the selected/single sample ---
                // Use the computed property sampleToDisplay
                if let sample = sampleToDisplay {
                    Text("Audio File:")
                        .font(.headline)
                    Text(sample.sourceFileURL.lastPathComponent)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("Waveform:")
                        .font(.headline)
                        .padding(.top)

                    // Display Waveform
                    if let totalFrames = audioFileTotalFrames, totalFrames > 0 {
                         SampleDetailWaveformView(
                             audioFileURL: sample.sourceFileURL,
                             segmentStartSample: sample.segmentStartSample,
                             segmentEndSample: sample.segmentEndSample,
                             totalFrames: totalFrames
                         )
                     } else {
                         VStack {
                             ProgressView()
                             Text("Loading Waveform...").font(.caption).foregroundColor(.secondary)
                         }
                         .frame(height: 150)
                         .frame(maxWidth: .infinity)
                         .padding(.horizontal)
                         .background(Color.secondary.opacity(0.1))
                         .cornerRadius(5)
                     }

                    // Start/End Points
                     HStack {
                        VStack(alignment: .leading) {
                            Text("Segment Start:")
                                .font(.headline)
                            Text("\(sample.segmentStartSample) samples")
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Segment End:")
                                .font(.headline)
                            Text("\(sample.segmentEndSample) samples")
                        }
                    }
                    .padding(.top)

                    Spacer() // Pushes details to the top within this block

                } else if samples.count > 1 {
                    // Only show this if picker is visible but nothing selected
                    Text("Select a sample above.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                }
                 // No final Spacer needed here, handled within blocks
            }
        }
        .padding()
        .onAppear {
             // Set initial picker selection if needed
             if samples.count > 1 && pickerSelectedSample == nil {
                 pickerSelectedSample = samples.first
             } 
             // Always load details for the initially relevant sample
             loadAudioFileDetails()
         }
         .onChange(of: samples) { // Reload if the input samples change
             print("SampleDetailView: Samples array changed, reloading details.")
             // Reset picker selection if necessary
             if samples.count > 1 {
                  pickerSelectedSample = samples.first
             } else {
                 pickerSelectedSample = nil
             }
             loadAudioFileDetails()
         }
         .onChange(of: pickerSelectedSample) { // Reload if picker selection changes
             print("SampleDetailView: Picker selection changed, reloading details.")
             loadAudioFileDetails()
         }
    }

    // --- Helper Function to Load Audio Details ---
    // Uses computed property sampleToDisplay
    func loadAudioFileDetails() {
        guard let sample = sampleToDisplay else {
            print("loadAudioFileDetails: No sample to display, clearing frame count.")
            audioFileTotalFrames = nil
            return
        }
        print("loadAudioFileDetails: Loading frames for \(sample.sourceFileURL.lastPathComponent)")
        Task {
            do {
                let file = try AVAudioFile(forReading: sample.sourceFileURL)
                await MainActor.run {
                     self.audioFileTotalFrames = file.length
                     print("Loaded audio file: \(sample.sourceFileURL.lastPathComponent), Frames: \(file.length)")
                 }
            } catch {
                print("Error loading AVAudioFile for \(sample.sourceFileURL.lastPathComponent): \(error)")
                await MainActor.run {
                     self.audioFileTotalFrames = nil
                 }
            }
        }
    }
}

// MARK: - Preview Provider
struct SampleDetailView_Previews: PreviewProvider {
    static let previewViewModel = SamplerViewModel()

    static var previews: some View {
        // Create some dummy sample data for the preview
        let dummyFileURL = URL(fileURLWithPath: "/path/to/dummy/sample.wav")
        let sample1 = MultiSamplePartData(
            name: "Sample 1",
            keyRangeMin: 60, keyRangeMax: 60,
            velocityRange: VelocityRangeData(min: 0, max: 90, crossfadeMin: 0, crossfadeMax: 90),
            sourceFileURL: dummyFileURL,
            segmentStartSample: 1000, segmentEndSample: 50000,
            absolutePath: dummyFileURL.path,
            originalAbsolutePath: dummyFileURL.path,
            sampleRate: 44100,
            fileSize: 102400,
            lastModDate: Date(),
            originalFileFrameCount: 100000 // Set a dummy total frame count
        )
        let sample2 = MultiSamplePartData(
            name: "Sample 2 High Vel",
            keyRangeMin: 60, keyRangeMax: 60,
            velocityRange: VelocityRangeData(min: 91, max: 127, crossfadeMin: 91, crossfadeMax: 127),
            sourceFileURL: dummyFileURL,
            segmentStartSample: 60000, segmentEndSample: 90000,
            absolutePath: dummyFileURL.path,
            originalAbsolutePath: dummyFileURL.path,
            sampleRate: 44100,
            fileSize: 102400,
            lastModDate: Date(),
            originalFileFrameCount: 100000 // Use same dummy total
        )

        VStack {
            // Preview with samples
            SampleDetailView(midiNote: 60, samples: [sample1, sample2])
                .environmentObject(previewViewModel)
                .border(Color.blue)
                .previewDisplayName("With Samples")
            
            Divider()
            
            // Preview without samples
            SampleDetailView(midiNote: 61, samples: [])
                .environmentObject(previewViewModel)
                .border(Color.red)
                .previewDisplayName("Without Samples")
        }
        .frame(height: 400) // Give the VStack a height for preview
    }
} 