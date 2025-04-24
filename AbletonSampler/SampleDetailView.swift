import SwiftUI
import AVFoundation // For audio file info
import AudioKit // For potential audio processing/waveform data
import AudioKitUI // For waveform view

// Placeholder for Waveform Drawing (Can refine later, potentially reuse/adapt from AudioSegmentEditorView)
// REMOVED: SampleDetailWaveformView - Replaced by direct use of AudioWaveform
/*
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
*/

struct SampleDetailView: View {
    @EnvironmentObject var viewModel: SamplerViewModel
    @Environment(\.dismiss) var dismiss

    // The MultiSamplePartData being displayed/edited
    @Binding var samplePart: MultiSamplePartData

    // --- State for Waveform Data ---
    @State private var waveformRMSData: [Float]? = nil // Store optional RMS data
    @State private var isLoadingWaveform: Bool = false

    // --- State for Editing ---
    // Store local copies of editable properties to avoid direct binding issues
    // if the underlying samplePart changes unexpectedly.
    @State private var localName: String
    @State private var localKeyRangeMin: Int
    @State private var localKeyRangeMax: Int
    @State private var localVelocityMin: Int
    @State private var localVelocityMax: Int

    // --- NEW: State for Waveform Zoom/Scroll ---
    @State private var horizontalZoom: CGFloat = 1.0
    @State private var scrollOffsetPercentage: CGFloat = 0.0
    // ------------------------------------------

    // Initializer to set up local state
    init(samplePart: Binding<MultiSamplePartData>) {
        self._samplePart = samplePart
        // Initialize local state from the bound samplePart's wrapped value
        _localName = State(initialValue: samplePart.wrappedValue.name)
        _localKeyRangeMin = State(initialValue: samplePart.wrappedValue.keyRangeMin)
        _localKeyRangeMax = State(initialValue: samplePart.wrappedValue.keyRangeMax)
        _localVelocityMin = State(initialValue: samplePart.wrappedValue.velocityRange.min)
        _localVelocityMax = State(initialValue: samplePart.wrappedValue.velocityRange.max)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Sample Details")
                .font(.title)
                .frame(maxWidth: .infinity, alignment: .center)

            // Use localName for editable Text/TextField
            TextField("Sample Name", text: $localName)
                .font(.title)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain) // More integrated look

            // Display File Path (Read-only from original binding)
            Text("Source: \(samplePart.sourceFileURL.lastPathComponent)")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .center)

            Divider()

            // --- UPDATED: Waveform Display with Segment Markers ---
            Group {
                if isLoadingWaveform {
                    ProgressView("Loading Waveform...")
                        .frame(height: 200) // Match height
                } else if viewModel.showingErrorAlert && waveformRMSData == nil {
                    Text("Error loading waveform: \(viewModel.errorAlertMessage ?? "Unknown error")")
                        .foregroundColor(.red)
                        .frame(height: 200) // Match height
                } else if let rmsData = waveformRMSData {
                     // Pass bindings for zoom/scroll
                     WaveformDisplayView(
                         waveformRMSData: rmsData,
                         horizontalZoom: $horizontalZoom,            // Pass binding
                         scrollOffsetPercentage: $scrollOffsetPercentage, // Pass binding
                         segmentStartSample: samplePart.segmentStartSample,
                         segmentEndSample: samplePart.segmentEndSample,
                         totalOriginalFrames: samplePart.originalFileFrameCount,
                         onSegmentUpdate: { newStart, newEnd in
                             // Call the ViewModel's update function when a marker is dragged
                             viewModel.updateSegmentBoundary(
                                 partID: samplePart.id,
                                 newStartSample: newStart,
                                 newEndSample: newEnd
                             )
                         }
                     )
                     // Match height of placeholders
                     .frame(height: 200)
                } else {
                    // Placeholder if no data and not loading (e.g., initial state or file issue)
                     Rectangle()
                         .fill(Color.gray.opacity(0.2))
                         .frame(height: 200)
                         .overlay(Text("Waveform not available"))
                }
            }
            .padding(.horizontal)

            // --- Add Sliders (if waveform data exists) ---
            if !isLoadingWaveform && waveformRMSData != nil && !waveformRMSData!.isEmpty {
                 HStack {
                     Text("Time:").frame(width: 80, alignment: .leading)
                     Slider(value: $horizontalZoom, in: 1.0...50.0) // Min zoom 1x
                     Text(String(format: "%.1fx", horizontalZoom)).frame(width: 40)
                 }
                 .padding(.horizontal)
                 .font(.caption)
                 // Note: Amplitude slider is internal to WaveformDisplayView, not needed here
            }
            // ---------------------------------------------

            Divider()

            // --- Editable Properties ---
            Group {
                 Text("Mapping").font(.title3)

                 HStack {
                     Text("Key Range:")
                     Spacer()
                     Picker("Min", selection: $localKeyRangeMin) {
                         ForEach(0..<128) { note in
                             Text("\(SamplerViewModel.noteNumberToName(note)) (\(note))").tag(note)
                         }
                     }
                     .labelsHidden()
                     .pickerStyle(.menu)
                     .onChange(of: localKeyRangeMin) { _, newValue in
                         localKeyRangeMin = max(0, min(newValue, localKeyRangeMax)) // Clamp min <= max
                     }

                     Text("to")

                     Picker("Max", selection: $localKeyRangeMax) {
                         ForEach(0..<128) { note in
                             Text("\(SamplerViewModel.noteNumberToName(note)) (\(note))").tag(note)
                         }
                     }
                     .labelsHidden()
                     .pickerStyle(.menu)
                     .onChange(of: localKeyRangeMax) { _, newValue in
                         localKeyRangeMax = max(localKeyRangeMin, min(newValue, 127)) // Clamp min <= max <= 127
                     }
                 }

                 HStack {
                    Text("Velocity Range:")
                    Spacer()
                    // Use TextFields for precise input, binding to local state
                    TextField("Min", value: $localVelocityMin, formatter: NumberFormatter.integer)
                         .frame(width: 50)
                         .multilineTextAlignment(.trailing)
                         .textFieldStyle(RoundedBorderTextFieldStyle())
                         .onChange(of: localVelocityMin) { _, newValue in
                             localVelocityMin = max(0, min(newValue, localVelocityMax)) // Clamp 0 <= min <= max
                         }
                     Text("to")
                     TextField("Max", value: $localVelocityMax, formatter: NumberFormatter.integer)
                         .frame(width: 50)
                         .multilineTextAlignment(.trailing)
                         .textFieldStyle(RoundedBorderTextFieldStyle())
                         .onChange(of: localVelocityMax) { _, newValue in
                              localVelocityMax = max(localVelocityMin, min(newValue, 127)) // Clamp min <= max <= 127
                         }
                 }

                // Display Round Robin Index (read-only for now)
                if let rrIndex = samplePart.roundRobinIndex {
                     HStack {
                         Text("Round Robin Index:")
                         Spacer()
                         Text("\(rrIndex)")
                     }
                 }

                 // Display Segment Boundaries (read-only for now)
                 // TODO: Make these editable via draggable markers on waveform
                 HStack {
                     Text("Segment Start:")
                     Spacer()
                     Text("\(samplePart.segmentStartSample) samples")
                 }
                 HStack {
                     Text("Segment End:")
                     Spacer()
                     Text("\(samplePart.segmentEndSample) samples")
                 }
                 HStack {
                    Text("Original File Length:")
                    Spacer()
                    Text("\(samplePart.originalFileFrameCount ?? -1) samples") // Display original length
                 }
                 .font(.caption)
                 .foregroundColor(.gray)


            } // End Group for Editable Properties

            Spacer() // Pushes buttons to bottom

            // --- Action Buttons ---
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button("Delete Sample Part", role: .destructive) {
                    // Confirmation dialog recommended here
                    viewModel.removeMultiSamplePart(id: samplePart.id)
                    dismiss()
                }
                Spacer()
                Button("Save Changes") {
                    saveChanges()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges) // Disable save if no changes
            }

        } // End Main VStack
        .padding()
        .task {
            // Load waveform when the view appears or samplePart changes
             await loadWaveformForDisplayedSample()
        }
        .onChange(of: samplePart.id) { _, newID in
            // Reload waveform if the samplePart binding points to a new part
            Task {
                await loadWaveformForDisplayedSample()
            }
            // Also reset local state to match the new samplePart
             resetLocalState()
        }
        // Observe changes to segment boundaries coming from the ViewModel/callback
        .onChange(of: samplePart.segmentStartSample) { _, _ in /* UI updates automatically */ }
        .onChange(of: samplePart.segmentEndSample) { _, _ in /* UI updates automatically */ }
        .alert("Error", isPresented: $viewModel.showingErrorAlert, actions: {
             Button("OK", role: .cancel) { }
         }, message: {
             Text(viewModel.errorAlertMessage ?? "An unknown error occurred.")
         })

    } // End Body

    // --- Helper: Check for Changes ---
    private var hasChanges: Bool {
        // Compare local state with the current value of the binding
        return localName != samplePart.name ||
               localKeyRangeMin != samplePart.keyRangeMin ||
               localKeyRangeMax != samplePart.keyRangeMax ||
               localVelocityMin != samplePart.velocityRange.min ||
               localVelocityMax != samplePart.velocityRange.max
    }

     // --- Helper: Reset Local State ---
     private func resetLocalState() {
         // Reset local state from the current value of the binding
         localName = samplePart.name
         localKeyRangeMin = samplePart.keyRangeMin
         localKeyRangeMax = samplePart.keyRangeMax
         localVelocityMin = samplePart.velocityRange.min
         localVelocityMax = samplePart.velocityRange.max
         print("Reset local state for part: \(samplePart.id)")
     }


    // --- Waveform Loading (REVERTED) ---
    @MainActor
    func loadWaveformForDisplayedSample() async {
        isLoadingWaveform = true
        waveformRMSData = nil // Clear previous data
        // Removed resetting samplesPerPixel state
        // Clear previous ViewModel error state related to waveform
        if viewModel.errorAlertMessage?.contains("waveform") ?? false {
             viewModel.clearError()
        }

        let fileUrl = samplePart.sourceFileURL
        // Start accessing security-scoped resource
        let securityScoped = fileUrl.startAccessingSecurityScopedResource()
        defer { if securityScoped { fileUrl.stopAccessingSecurityScopedResource() } }

        print("Loading waveform for: \(fileUrl.lastPathComponent)")
        // Call ViewModel's function - Expects [Float]?
        let rmsDataResult = await viewModel.getWaveformRMSData(for: fileUrl)

        // Update state on the main actor
        await MainActor.run {
            if let rmsData = rmsDataResult {
                if !rmsData.isEmpty {
                    self.waveformRMSData = rmsData // Store data
                    // Removed storing samplesPerPixel
                    print(" -> Waveform loaded successfully (\(rmsData.count) samples)")
                } else {
                    viewModel.showError("Waveform generation resulted in empty data.")
                    print(" -> Waveform generation gave empty data.")
                }
            } else {
                // ... (Handle nil result)
                 print(" -> Waveform generation failed or returned nil.")
            }
            self.isLoadingWaveform = false
        }
    }

    // --- Save Changes ---
    func saveChanges() {
        // Create a mutable copy of the sample part's current value
        var updatedPart = samplePart

        // Update the properties of the copy from local state
        updatedPart.name = localName
        updatedPart.keyRangeMin = localKeyRangeMin
        updatedPart.keyRangeMax = localKeyRangeMax
        // Use original crossfade values when creating the new VelocityRangeData
        updatedPart.velocityRange = VelocityRangeData(
            min: localVelocityMin,
            max: localVelocityMax,
            crossfadeMin: samplePart.velocityRange.crossfadeMin, // Preserve original crossfade
            crossfadeMax: samplePart.velocityRange.crossfadeMax  // Preserve original crossfade
        )

        // Call ViewModel to update the actual data source
        viewModel.updateMultiSamplePart(updatedPart)
        print("Saved changes for part: \(updatedPart.id)")
    }

} // End Struct

// MARK: - Preview

struct SampleDetailView_Previews: PreviewProvider {
    // Static state for the preview binding
    @State static var previewPart = MultiSamplePartData.example

    static var previews: some View {
        // Pass the binding to the state variable
        SampleDetailView(samplePart: $previewPart)
            .environmentObject(SamplerViewModel()) // Provide a ViewModel
            .frame(width: 400, height: 600) // Give it some size for preview
    }
}

// MARK: - Helper Extensions (e.g., NumberFormatter)

extension NumberFormatter {
    static var integer: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        return formatter
    }
}

// Add an example to MultiSamplePartData for previews
extension MultiSamplePartData {
    static var example: MultiSamplePartData {
        MultiSamplePartData(
            name: "Preview Sample",
            keyRangeMin: 60, // C4
            keyRangeMax: 60, // C4
            velocityRange: VelocityRangeData(min: 0, max: 127, crossfadeMin: 0, crossfadeMax: 127), // Use correct initializer
            sourceFileURL: URL(fileURLWithPath: "/path/to/fake/preview.wav"), // Needs a real placeholder?
            segmentStartSample: 1000,
            segmentEndSample: 44100,
            roundRobinIndex: nil,
            relativePath: "preview.wav", // Assuming it's in Samples/Imported for preview
            absolutePath: "/path/to/fake/preview.wav", // Placeholder
            originalAbsolutePath: "/path/to/fake/preview.wav", // Placeholder
            // Corrected order: sampleRate, fileSize, crc, lastModDate THEN originalFileFrameCount
            sampleRate: 44100.0, // Example sample rate
            fileSize: 176400, // Example file size
            crc: nil, // CRC usually calculated
            lastModDate: Date(), // Example date
            originalFileFrameCount: 88200 // Example frame count
            // Other properties use defaults or calculated values
        )
    }
} 
