import SwiftUI
import AVFoundation
import AudioKit // Import the main AudioKit framework
import AudioKitUI // Import the UI components

// Placeholder for the waveform view component
struct WaveformView: View {
    // TODO: Implement waveform drawing logic
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 150) // Example height
            .overlay(Text("Waveform Placeholder").foregroundColor(.white))
    }
}

// --- UPDATED: Marker View with Draggable Handle ---
struct MarkerView: View {
    // Binding to indicate if this specific marker is being dragged
    // This can be used for visual feedback (e.g., changing color)
    @Binding var isBeingDragged: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Draggable Handle (Flag)
            Circle()
                .fill(isBeingDragged ? Color.yellow : Color.red) // Highlight when dragged
                .frame(width: 12, height: 12)
                .shadow(radius: 2)
                .padding(.bottom, -1) // Overlap slightly with the line

            // Marker Line
            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: 150)
                .opacity(0.7)
        }
        .contentShape(Rectangle().size(width: 20, height: 170)) // Increase tappable area
    }
}

struct AudioSegmentEditorView: View {
    @EnvironmentObject var viewModel: SamplerViewModel
    @Environment(\.dismiss) var dismiss

    let audioFileURL: URL

    // --- State for Audio Data & Waveform ---
    @State private var audioFile: AVAudioFile? = nil
    @State private var audioInfo: String = "Loading audio..."
    @State private var totalFrames: Int64? = nil
    @State private var waveformWidth: CGFloat = 0
    // --- UPDATED: State for waveform RMS data ---
    @State private var waveformRMSData: [Float] = [] // Store calculated RMS values
    @State private var isLoadingWaveform = true

    // --- State for Markers & Segments ---
    @State private var markers: [Double] = []
    @State private var selectedSegmentIndex: Int? = nil

    // --- State for Mapping ---
    @State private var targetMidiNote: Int = 0
    let availableMidiNotes = 0..<12

    // --- NEW: State for Dragging Markers ---
    @State private var draggedMarkerIndex: Int? = nil
    // Use GestureState for smooth updates during drag without complex state management
    @GestureState private var dragOffset: CGSize = .zero

    // --- NEW: Auto-Mapping State ---
    @State private var autoMapStartNote: Int = 0 // Starting note for note mapping
    @State private var velocityMapTargetNote: Int = 0 // Target note for velocity mapping

    // --- Computed Property: Number of Segments ---
    private var numberOfSegments: Int {
        markers.count + 1
    }

    var body: some View {
        VStack(spacing: 15) {
            Text("Audio Segment Editor")
                .font(.title2)

            Text("Editing: \(audioFileURL.lastPathComponent)")
                .font(.caption)
                .lineLimit(1)

            // --- Waveform Display using AudioKitUI --- 
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    if isLoadingWaveform {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.gray.opacity(0.3))
                    } else if !waveformRMSData.isEmpty {
                        AudioWaveform(rmsVals: waveformRMSData)
                            .foregroundColor(.accentColor)
                            .onAppear {
                                self.waveformWidth = geometry.size.width
                                print("Waveform Width: \(self.waveformWidth)")
                            }
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(Text("Could not load waveform").foregroundColor(.white))
                    }

                    // --- UPDATED: Display Markers with Drag Gesture ---
                    ForEach(markers.indices, id: \.self) { index in
                        let isDraggingThisMarker = (draggedMarkerIndex == index)
                        let markerValue = markers[index]
                        let initialXPosition = calculateMarkerXPosition(markerValue: markerValue)

                        // Calculate current position based on drag offset IF this marker is dragged
                        let currentXPosition = isDraggingThisMarker ? initialXPosition + dragOffset.width : initialXPosition

                        MarkerView(isBeingDragged: .constant(isDraggingThisMarker))
                            .position(x: currentXPosition, y: geometry.size.height / 2) // Center marker vertically
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .updating($dragOffset) { value, state, _ in
                                        // Update GestureState smoothly during drag
                                        state = value.translation
                                        // Set the index ONLY when drag starts
                                        DispatchQueue.main.async {
                                             if self.draggedMarkerIndex == nil {
                                                 self.draggedMarkerIndex = index
                                             }
                                         }
                                    }
                                    .onEnded { value in
                                        // Finalize position on drag end
                                        finalizeMarkerDrag(index: index, dragTranslation: value.translation)
                                        // Reset dragged index
                                        self.draggedMarkerIndex = nil
                                    }
                            )
                    }
                }
                .contentShape(Rectangle()) // Make the whole ZStack tappable for adding markers
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                     // Add marker only if not dragging and waveform is loaded
                     if draggedMarkerIndex == nil, !isLoadingWaveform, !waveformRMSData.isEmpty {
                         addMarker(at: value.location)
                     }
                 })
                 .onAppear { // Store initial width
                     self.waveformWidth = geometry.size.width
                     print("Initial Waveform Width: \(self.waveformWidth)")
                 }
                 .onChange(of: geometry.size.width) { oldValue, newValue in
                    if waveformWidth != newValue && newValue > 0 {
                         self.waveformWidth = newValue
                         print("Waveform Width Changed: \(self.waveformWidth)")
                     }
                 }
            }
            .frame(height: 150)
            .padding(.horizontal)

            // --- Segment Information & Mapping ---
            Text(audioInfo)
                .font(.footnote)

            Text("Segments Defined: \(numberOfSegments)")
                .font(.footnote)

            Picker("Select Segment", selection: $selectedSegmentIndex) {
                 Text("None").tag(nil as Int?)
                 ForEach(0..<numberOfSegments, id: \.self) { index in
                     Text("Segment \(index + 1)").tag(index as Int?)
                 }
             }
             .pickerStyle(.segmented)

            // --- MIDI Note Mapping ---
             if let segmentIndex = selectedSegmentIndex {
                 HStack {
                     Text("Map Segment \(segmentIndex + 1) to:")
                     Picker("Target MIDI Note", selection: $targetMidiNote) { // Bind to state variable
                         ForEach(availableMidiNotes, id: \.self) { note in
                             Text(KeyZoneView.midiNoteNameStatic(for: note)).tag(note)
                         }
                     }
                     .pickerStyle(.menu)
                     .labelsHidden() // Hide the picker label itself

                     Spacer()

                     Button("Assign Segment") {
                         assignSegmentToNote(segmentIndex: segmentIndex)
                     }
                     .buttonStyle(.bordered)
                 }
             } else {
                 Text("Select a segment above to map it to a MIDI note.")
                     .font(.footnote)
                     .foregroundColor(.secondary)
                     .frame(height: 30) // Keep layout consistent
             }

            Divider().padding(.vertical, 5)

            // --- NEW: Auto-Mapping Section ---
            VStack(alignment: .leading, spacing: 10) {
                Text("Automatic Mapping").font(.headline)

                // Map to Notes
                HStack {
                    Button("Map Segments to Notes Starting From:") {
                        autoMapSegmentsToNotes(startNote: autoMapStartNote)
                    }
                    .disabled(numberOfSegments == 0)

                    Picker("Start Note", selection: $autoMapStartNote) {
                        ForEach(availableMidiNotes, id: \.self) { note in
                            Text(KeyZoneView.midiNoteNameStatic(for: note)).tag(note)
                        }
                    }
                    .labelsHidden()
                }

                // Map to Velocity Zones
                HStack {
                    Button("Map Segments to Velocity Zones on Note:") {
                        autoMapSegmentsToVelocity(targetNote: velocityMapTargetNote)
                    }
                    .disabled(numberOfSegments == 0)

                    Picker("Target Note", selection: $velocityMapTargetNote) {
                        ForEach(availableMidiNotes, id: \.self) { note in
                            Text(KeyZoneView.midiNoteNameStatic(for: note)).tag(note)
                        }
                    }
                    .labelsHidden()
                }
            }
            // -----------------------------

            Spacer() // Push controls down

            // --- Action Buttons ---
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 550, minHeight: 500) // Increased size for new controls
        .task(loadAudioAndWaveform) // Use .task for async work tied to view lifetime
    }

    // --- Helper Functions ---

    // --- UPDATED: Use async/await and extract waveform data --- 
    @MainActor
    private func loadAudioAndWaveform() async {
        print("Loading audio data and waveform for: \(audioFileURL.path)")
        isLoadingWaveform = true
        waveformRMSData = []
        audioFile = nil
        totalFrames = nil
        audioInfo = "Loading..."

        do {
            let file = try AVAudioFile(forReading: audioFileURL)
            let format = file.processingFormat
            let frameCount = file.length

            // Basic info update
            self.audioFile = file
            self.totalFrames = frameCount
            let duration = Double(frameCount) / format.sampleRate
            self.audioInfo = String(format: "Duration: %.2f s | Rate: %.0f Hz | Frames: %lld",
                                    duration, format.sampleRate, frameCount)

            print("Audio info loaded. Frames: \(frameCount)")

            // --- Extract Waveform Data --- 
            // Read audio data into a buffer
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                throw NSError(domain: "AudioLoadError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create buffer"])
            }
            try file.read(into: buffer)

            // Calculate RMS or peak samples for display
            // This is a simplified example - adjust `samplesPerPixel` for performance/detail trade-off
            let samplesPerPixel = 1024 // Process N samples for each display point
            let displaySamplesCount = max(1, Int(frameCount) / samplesPerPixel)
            var rmsSamples = [Float](repeating: 0.0, count: displaySamplesCount)

            guard let floatChannelData = buffer.floatChannelData else {
                 throw NSError(domain: "AudioLoadError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not get float channel data"])
            }
            // Assuming mono or use first channel
            let channelData = floatChannelData[0]

            for i in 0..<displaySamplesCount {
                let startSample = i * samplesPerPixel
                let endSample = min(startSample + samplesPerPixel, Int(frameCount))
                let blockSampleCount = endSample - startSample

                if blockSampleCount > 0 {
                    var sumOfSquares: Float = 0.0
                    // Sum squares of samples in the block
                    for j in startSample..<endSample {
                        let sample = channelData[j]
                        sumOfSquares += sample * sample
                    }
                    // Calculate RMS for the block
                    let meanSquare = sumOfSquares / Float(blockSampleCount)
                    rmsSamples[i] = sqrt(meanSquare)
                } else {
                    // Handle case where blockSampleCount is 0 (shouldn't happen with max(1,...) above)
                    rmsSamples[i] = 0.0 
                }
            }
            // --------------------------

            print("Waveform RMS data extracted. Display samples: \(rmsSamples.count)")

            self.waveformRMSData = rmsSamples
            self.isLoadingWaveform = false

        } catch {
            let errorMsg = "Error loading audio/waveform: \(error.localizedDescription)"
            print(errorMsg)
            self.audioInfo = errorMsg
            self.isLoadingWaveform = false
            self.waveformRMSData = []
            viewModel.showError("Failed to load audio file: \(error.localizedDescription)")
        }
    }

    private func addMarker(at point: CGPoint) {
        guard waveformWidth > 0 else { // Ensure width is calculated
            print("Cannot add marker: Waveform width not yet available.")
            return
        }
        // Calculate normalized position (0.0 to 1.0)
        let normalizedPosition = max(0, min(1, point.x / waveformWidth))

        // Avoid adding duplicate markers very close to each other (optional)
        if !markers.contains(where: { abs($0 - normalizedPosition) < (1 / waveformWidth) }) {
            markers.append(normalizedPosition)
            markers.sort() // Keep markers sorted by position
            print("Added marker at normalized position: \(normalizedPosition)")
        } else {
            print("Marker position too close to existing marker. Ignoring.")
        }
    }

    // --- UPDATED: Calculates X position only ---
    private func calculateMarkerXPosition(markerValue: Double) -> CGFloat {
        return markerValue * waveformWidth
    }

    // --- NEW: Function to handle final drag position update ---
    private func finalizeMarkerDrag(index: Int, dragTranslation: CGSize) {
        guard index >= 0 && index < markers.count else { return }
        guard waveformWidth > 0 else { return }

        // Get original position
        let originalValue = markers[index]
        let originalX = calculateMarkerXPosition(markerValue: originalValue)

        // Calculate new position based on drag
        let newX = originalX + dragTranslation.width
        let newNormalizedValue = max(0, min(1, newX / waveformWidth))

        // Update the marker's position in the array
        markers[index] = newNormalizedValue

        // Re-sort the array after modification
        markers.sort()

        print("Moved marker \(index) to normalized position: \(newNormalizedValue)")
    }

    private func assignSegmentToNote(segmentIndex: Int) {
        guard let frames = totalFrames, frames > 0 else {
            print("Cannot assign segment: Total frames not available or zero.")
            viewModel.showError("Audio file information not fully loaded.")
            return
        }
        guard segmentIndex >= 0 && segmentIndex < numberOfSegments else {
            print("Invalid segment index: \(segmentIndex) for \(numberOfSegments) segments")
            return
        }

        // Determine start and end markers for the segment
        let startMarkerValue = (segmentIndex == 0) ? 0.0 : markers[segmentIndex - 1]
        let endMarkerValue = (segmentIndex == markers.count) ? 1.0 : markers[segmentIndex]

        // Convert normalized marker values to sample frames
        let startSample = Int64(startMarkerValue * Double(frames))
        let endSample = Int64(endMarkerValue * Double(frames))

        // Ensure startSample is strictly less than endSample
        guard startSample < endSample else {
            print("Cannot assign segment: Start sample (\(startSample)) is not less than end sample (\(endSample)).")
            viewModel.showError("Selected segment has zero length.")
            return
        }

        // Call the ViewModel function
        print("Assigning Segment \(segmentIndex + 1) [Samples: \(startSample) - \(endSample)] to Note \(targetMidiNote)")
        viewModel.addSampleSegment(
            sourceFileURL: audioFileURL,
            segmentStartSample: startSample,
            segmentEndSample: endSample,
            targetNote: targetMidiNote
            // segmentName could be customized here if needed
        )

        // Optional: Give feedback to the user
        // e.g., show a temporary confirmation message

        // Deselect segment after assigning (optional)
        // selectedSegmentIndex = nil
    }

    // --- NEW: Auto-Mapping Functions ---

    /// Maps each segment to a consecutive MIDI note, starting from `startNote`.
    private func autoMapSegmentsToNotes(startNote: Int) {
        guard let frames = totalFrames, frames > 0 else {
            viewModel.showError("Audio file not fully loaded for auto-mapping.")
            return
        }
        guard numberOfSegments > 0 else {
             viewModel.showError("No segments defined by markers.")
             return
         }

        print("Auto-mapping \(numberOfSegments) segments to notes starting from \(startNote)...")

        // It's safer to collect all segment data first, then pass to ViewModel
        // to handle potential replacements in one go, but for simplicity, we add one by one.

        for segmentIndex in 0..<numberOfSegments {
            let targetNote = startNote + segmentIndex
            // Clamp target note to the available range (0-11 for now, or 0-127 if needed)
            let clampedTargetNote = max(0, min(11, targetNote))
            if targetNote != clampedTargetNote {
                print("Warning: Target note \(targetNote) clamped to \(clampedTargetNote).")
            }

            let startMarkerValue = (segmentIndex == 0) ? 0.0 : markers[segmentIndex - 1]
            let endMarkerValue = (segmentIndex == markers.count) ? 1.0 : markers[segmentIndex]

            let startSample = Int64(startMarkerValue * Double(frames))
            let endSample = Int64(endMarkerValue * Double(frames))

            guard startSample < endSample else {
                print("Skipping zero-length segment \(segmentIndex + 1) for note mapping.")
                continue // Skip empty segments
            }

            print(" -> Mapping Segment \(segmentIndex + 1) [\(startSample)-\(endSample)] to Note \(clampedTargetNote)")
            viewModel.addSampleSegment(
                sourceFileURL: audioFileURL,
                segmentStartSample: startSample,
                segmentEndSample: endSample,
                targetNote: clampedTargetNote
                // Default name and full velocity range are used
            )
        }
        print("Finished auto-mapping to notes.")
        // Optionally dismiss the view after auto-mapping?
        // dismiss()
    }

    /// Maps all segments to a single `targetNote` with distributed velocity zones.
    private func autoMapSegmentsToVelocity(targetNote: Int) {
        guard let frames = totalFrames, frames > 0 else {
            viewModel.showError("Audio file not fully loaded for auto-mapping.")
            return
        }
        guard numberOfSegments > 0 else {
             viewModel.showError("No segments defined by markers.")
             return
         }

        print("Auto-mapping \(numberOfSegments) segments to velocity zones on note \(targetNote)...")

        // --- Calculate Velocity Ranges (Simplified Separate Logic) ---
        // Ideally, reuse or call SamplerViewModel logic
        var velocityRanges: [VelocityRangeData] = []
        if numberOfSegments == 1 {
            velocityRanges = [.fullRange]
        } else {
            let totalVelocityRange = 128.0
            let baseWidth = totalVelocityRange / Double(numberOfSegments)
            var currentMin = 0.0
            for i in 0..<numberOfSegments {
                let calculatedMax = currentMin + baseWidth - 1.0
                var zoneMin = Int(currentMin.rounded(.down))
                var zoneMax = Int(calculatedMax.rounded(.down))
                if i == numberOfSegments - 1 { zoneMax = 127 }
                zoneMin = max(0, zoneMin)
                zoneMax = max(zoneMin, zoneMax)
                zoneMax = min(127, zoneMax)
                let range = VelocityRangeData(min: zoneMin, max: zoneMax, crossfadeMin: zoneMin, crossfadeMax: zoneMax)
                velocityRanges.append(range)
                currentMin = Double(zoneMax) + 1.0
            }
             // Minimal adjustment for last range edge case
            if var lastRange = velocityRanges.popLast() { // Check if not empty
                if lastRange.max < 127 && numberOfSegments > 1 {
                     if var secondLastRange = velocityRanges.popLast() { // Check again
                        secondLastRange = VelocityRangeData(min: secondLastRange.min, max: max(secondLastRange.min, lastRange.min - 1), crossfadeMin: secondLastRange.crossfadeMin, crossfadeMax: max(secondLastRange.min, lastRange.min - 1))
                        velocityRanges.append(secondLastRange)
                    }
                    lastRange = VelocityRangeData(min: lastRange.min, max: 127, crossfadeMin: lastRange.crossfadeMin, crossfadeMax: 127)
                }
                velocityRanges.append(lastRange)
            }
        }
        guard velocityRanges.count == numberOfSegments else {
            print("Error: Velocity range calculation mismatch.")
            viewModel.showError("Internal error calculating velocity ranges.")
            return
        }
        // --- End Velocity Calculation ---


        // Collect segment data first before calling ViewModel
        var segmentInfos: [(start: Int64, end: Int64, velocity: VelocityRangeData)] = []
        for segmentIndex in 0..<numberOfSegments {
            let startMarkerValue = (segmentIndex == 0) ? 0.0 : markers[segmentIndex - 1]
            let endMarkerValue = (segmentIndex == markers.count) ? 1.0 : markers[segmentIndex]
            let startSample = Int64(startMarkerValue * Double(frames))
            let endSample = Int64(endMarkerValue * Double(frames))
            let velocityRange = velocityRanges[segmentIndex]

            if startSample < endSample {
                 segmentInfos.append((start: startSample, end: endSample, velocity: velocityRange))
                 print(" -> Preparing Segment \(segmentIndex + 1) [\(startSample)-\(endSample)] for Vel [\(velocityRange.min)-\(velocityRange.max)]")
            } else {
                 print("Skipping zero-length segment \(segmentIndex + 1) for velocity mapping.")
            }
        }
        
        // Call ViewModel function for each prepared segment info
        print("Submitting \(segmentInfos.count) segments to ViewModel for note \(targetNote)...")
        for info in segmentInfos {
             viewModel.addSampleSegment(
                 sourceFileURL: audioFileURL,
                 segmentStartSample: info.start,
                 segmentEndSample: info.end,
                 targetNote: targetNote,
                 velocityRange: info.velocity // Pass the specific range
             )
        }

        print("Finished auto-mapping to velocity zones.")
        // Optionally dismiss the view after auto-mapping?
        // dismiss()
    }
}

// --- Preview ---
struct AudioSegmentEditorView_Previews: PreviewProvider {
    static var previews: some View {
        // --- FIX: Correct guard let usage ---
        // Use nil-coalescing operator ?? to provide the fallback URL
        let dummyURL = Bundle.main.url(forResource: "TestSound", withExtension: "wav")
                      ?? URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")

        // The guard is no longer needed here as dummyURL is guaranteed to be non-nil
        // by the fallback. If even the fallback might fail (e.g., invalid path),
        // you might structure it differently, but for these typical cases, this is fine.
        // guard let urlToUse = dummyURL else { ... }

        let dummyViewModel = SamplerViewModel()

        return AudioSegmentEditorView(audioFileURL: dummyURL)
            .environmentObject(dummyViewModel)
            .previewLayout(.sizeThatFits)
            .eraseToAnyView()
    }
}

// Helper to erase type for preview
extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
} 