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

    // --- NEW: Transient Detection State ---
    @State private var transientThreshold: Double = 0.1 // Default sensitivity (0.0 to 1.0)
    // Higher value = less sensitive (fewer markers), Lower value = more sensitive (more markers)

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

            // --- Marker Controls ---
             HStack {
                 Button("Clear All Markers") {
                     markers.removeAll()
                     selectedSegmentIndex = nil // Deselect segment if markers are cleared
                 }
                 .disabled(markers.isEmpty)

                 Spacer()

                 // --- NEW: Transient Detection Controls ---
                 VStack(alignment: .trailing) {
                     Button("Detect Transients") {
                         detectAndSetTransients()
                     }
                     .disabled(isLoadingWaveform || waveformRMSData.isEmpty)

                     HStack {
                         Text("Sensitivity:")
                         Slider(value: $transientThreshold, in: 0.01...1.0) // Avoid 0 threshold
                             .frame(width: 100)
                     }
                     .font(.caption)
                 }
                 // -------------------------------------
             }
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
        .frame(minWidth: 550, minHeight: 550) // Increased height for new controls
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

    // --- NEW: Transient Detection Logic ---

    /// Detects transients based on the `transientThreshold` and updates the `markers` state.
    private func detectAndSetTransients() {
        guard !waveformRMSData.isEmpty else {
            print("Cannot detect transients: Waveform data not available.")
            return
        }

        // Invert threshold: Slider goes 0.01 (high sensitivity) to 1.0 (low sensitivity)
        // We want a *lower* internal threshold for *higher* sensitivity.
        // A simple inversion like (1.0 - threshold) can work. Adjust range/scaling as needed.
        let internalThreshold = 1.0 - transientThreshold
        print("Detecting transients with internal threshold: \(internalThreshold) (Slider: \(transientThreshold))")

        let detectedMarkers = findTransients(in: waveformRMSData, threshold: Float(internalThreshold))

        print("Detected \(detectedMarkers.count) transients.")
        // Replace existing markers with detected ones
        self.markers = detectedMarkers
        self.selectedSegmentIndex = nil // Deselect any selected segment
    }

    /// Analyzes waveform data to find transient points.
    /// - Parameter data: Array of RMS or similar amplitude values.
    /// - Parameter threshold: Sensitivity threshold (lower value detects more).
    /// - Returns: An array of normalized marker positions (0.0 to 1.0).
    private func findTransients(in data: [Float], threshold: Float) -> [Double] {
        guard data.count > 1 else { return [] }

        var transientPositions: [Double] = []
        let dataCount = data.count
        let minEnergyThreshold: Float = 0.005 // Ignore very low energy changes

        // Calculate differences between consecutive RMS values
        var differences: [Float] = []
        for i in 0..<(dataCount - 1) {
            let diff = abs(data[i+1] - data[i])
            differences.append(diff)
        }

        // Find the maximum difference for normalization (optional but good)
        guard let maxDifference = differences.max(), maxDifference > 0 else {
            print("No significant differences found in RMS data.")
            return [] // No differences to analyze
        }

        print("Max RMS difference: \(maxDifference)")

        // Detect peaks in the differences that exceed the threshold
        for i in 0..<differences.count {
            let normalizedDiff = differences[i] / maxDifference // Normalize difference

            // Check if the normalized difference exceeds the threshold
            // AND if the energy at this point is above a minimum threshold
            if normalizedDiff > threshold && data[i+1] > minEnergyThreshold {

                // Add a marker slightly *before* the detected rise (at index i)
                let normalizedPosition = Double(i) / Double(dataCount - 1) // Normalize index

                // Avoid adding markers too close to each other (simple debounce)
                let minDistance: Double = 0.01 // e.g., 1% of waveform width
                if let lastMarker = transientPositions.last {
                    if (normalizedPosition - lastMarker) < minDistance {
                        // print("Skipping transient too close to previous one at \(normalizedPosition)")
                        continue // Skip if too close
                    }
                }

                 // Add a small offset to place marker slightly before the detected point if needed
                // let offset = -0.005 // e.g., shift back 0.5%
                // let finalPosition = max(0.0, min(1.0, normalizedPosition + offset))

                let finalPosition = max(0.0, min(1.0, normalizedPosition)) // Use original position for now

                transientPositions.append(finalPosition)
                // print("Transient detected at index \(i), normalized: \(finalPosition)")
            }
        }

        // Ensure markers are sorted
        transientPositions.sort()
        return transientPositions
    }

    // --- End Transient Detection Logic ---

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

    /// Maps each segment defined by markers to a consecutive MIDI note, starting from `startNote`.
    /// Skips the implicit segment from 0.0 to the first marker unless a marker exists near 0.0.
    private func autoMapSegmentsToNotes(startNote: Int) {
        guard let frames = totalFrames, frames > 0 else {
            viewModel.showError("Audio file not fully loaded for auto-mapping.")
            return
        }
        // Require at least one marker to define any segments
        guard !markers.isEmpty else {
             viewModel.showError("No markers defined to create segments.")
             return
        }

        // Determine if the first marker is effectively at the start
        let tolerance = 0.001 // How close to 0.0 is considered the start
        let includeFirstImplicitSegment = markers[0] < tolerance

        // Calculate the number of segments to map based on markers
        let numberOfMappableSegments = includeFirstImplicitSegment ? markers.count + 1 : markers.count

        // Calculate the starting index for the loop
        let loopStartIndex = includeFirstImplicitSegment ? 0 : 1
        // Calculate the index offset for accessing the markers array
        let markerIndexOffset = includeFirstImplicitSegment ? 1 : 0

        print("Auto-mapping \(numberOfMappableSegments) segments to notes starting from \(startNote)...")
        print(includeFirstImplicitSegment ? "Including implicit segment from start." : "Skipping implicit segment from start.")

        for segmentLoopIndex in loopStartIndex..<(markers.count + 1) {
            // Calculate the effective segment index relative to the potential full list of segments (including implicit first)
            let effectiveSegmentIndex = segmentLoopIndex
            // Calculate the target MIDI note, adjusted by how many segments we actually map
            let noteOffset = segmentLoopIndex - loopStartIndex
            let targetNote = startNote + noteOffset

            // Clamp target note
            let clampedTargetNote = max(0, min(127, targetNote)) // Use 0-127 range
            if targetNote != clampedTargetNote {
                print("Warning: Target note \(targetNote) clamped to \(clampedTargetNote).")
            }

            // Determine start and end markers based on the effective segment index
            let startMarkerValue = (effectiveSegmentIndex == 0) ? 0.0 : markers[effectiveSegmentIndex - 1]
            let endMarkerValue = (effectiveSegmentIndex == markers.count) ? 1.0 : markers[effectiveSegmentIndex]

            let startSample = Int64(startMarkerValue * Double(frames))
            let endSample = Int64(endMarkerValue * Double(frames))

            guard startSample < endSample else {
                print("Skipping zero-length segment \(effectiveSegmentIndex + 1) for note mapping.")
                continue // Skip empty segments
            }

            print(" -> Mapping Segment \(effectiveSegmentIndex + 1) [\(startSample)-\(endSample)] to Note \(clampedTargetNote)")
            viewModel.addSampleSegment(
                sourceFileURL: audioFileURL,
                segmentStartSample: startSample,
                segmentEndSample: endSample,
                targetNote: clampedTargetNote
            )
        }
        print("Finished auto-mapping to notes.")
    }

    /// Maps segments defined by markers to a single `targetNote` with distributed velocity zones.
    /// Skips the implicit segment from 0.0 to the first marker unless a marker exists near 0.0.
    private func autoMapSegmentsToVelocity(targetNote: Int) {
        guard let frames = totalFrames, frames > 0 else {
            viewModel.showError("Audio file not fully loaded for auto-mapping.")
            return
        }
        // Require at least one marker
        guard !markers.isEmpty else {
            viewModel.showError("No markers defined to create segments.")
            return
        }

        // Determine if the first marker is effectively at the start
        let tolerance = 0.001
        let includeFirstImplicitSegment = markers[0] < tolerance

        // Calculate the number of segments to map
        let numberOfMappableSegments = includeFirstImplicitSegment ? markers.count + 1 : markers.count
        // Calculate the starting index for the loop
        let loopStartIndex = includeFirstImplicitSegment ? 0 : 1

        print("Auto-mapping \(numberOfMappableSegments) segments to velocity zones on note \(targetNote)...")
        print(includeFirstImplicitSegment ? "Including implicit segment from start." : "Skipping implicit segment from start.")

        // --- Calculate Velocity Ranges for the *mappable* segments --- 
        var velocityRanges: [VelocityRangeData] = []
        if numberOfMappableSegments == 1 {
            // If only one segment is being mapped (either explicit or implicit-included)
            velocityRanges = [.fullRange]
        } else if numberOfMappableSegments > 1 {
            let totalVelocityRange = 128.0
            let baseWidth = totalVelocityRange / Double(numberOfMappableSegments)
            var currentMin = 0.0
            for i in 0..<numberOfMappableSegments { // Iterate for the actual number of segments being mapped
                let calculatedMax = currentMin + baseWidth - 1.0
                var zoneMin = Int(currentMin.rounded(.down))
                var zoneMax = Int(calculatedMax.rounded(.down))
                // Ensure the very last zone reaches 127
                if i == numberOfMappableSegments - 1 { zoneMax = 127 }
                zoneMin = max(0, zoneMin)
                zoneMax = max(zoneMin, zoneMax) // Ensure max >= min
                zoneMax = min(127, zoneMax)
                let range = VelocityRangeData(min: zoneMin, max: zoneMax, crossfadeMin: zoneMin, crossfadeMax: zoneMax)
                velocityRanges.append(range)
                currentMin = Double(zoneMax) + 1.0
            }
            // Refined adjustment for last range edge case
            if velocityRanges.count > 1 { // Need at least 2 ranges for this adjustment
                if var lastRange = velocityRanges.popLast() { // Use optional binding
                    if lastRange.max < 127 {
                        lastRange = VelocityRangeData(min: lastRange.min, max: 127, crossfadeMin: lastRange.crossfadeMin, crossfadeMax: 127)
                        if var secondLastRange = velocityRanges.popLast() { // Check again
                             // Adjust the second-to-last range to end just before the last one starts
                            let newSecondLastMax = max(secondLastRange.min, lastRange.min - 1)
                            secondLastRange = VelocityRangeData(min: secondLastRange.min, max: newSecondLastMax, crossfadeMin: secondLastRange.crossfadeMin, crossfadeMax: newSecondLastMax)
                            velocityRanges.append(secondLastRange)
                        } else {
                            // If there was only one range before, adjust its max (shouldn't happen if count > 1)
                            lastRange = VelocityRangeData(min: 0, max: 127, crossfadeMin: 0, crossfadeMax: 127)
                        }
                    }
                     velocityRanges.append(lastRange)
                }
            }
        }

        guard velocityRanges.count == numberOfMappableSegments else {
            print("Error: Velocity range calculation mismatch. Expected \(numberOfMappableSegments), got \(velocityRanges.count)")
            viewModel.showError("Internal error calculating velocity ranges.")
            return
        }
        // --- End Velocity Calculation ---

        // Collect segment data first before calling ViewModel
        var segmentInfos: [(start: Int64, end: Int64, velocity: VelocityRangeData)] = []

        for segmentLoopIndex in loopStartIndex..<(markers.count + 1) {
            // Calculate the effective segment index relative to the potential full list
            let effectiveSegmentIndex = segmentLoopIndex
            // Calculate the index for the velocity range array (0-based for mapped segments)
            let velocityRangeIndex = segmentLoopIndex - loopStartIndex

            // Get segment boundaries
            let startMarkerValue = (effectiveSegmentIndex == 0) ? 0.0 : markers[effectiveSegmentIndex - 1]
            let endMarkerValue = (effectiveSegmentIndex == markers.count) ? 1.0 : markers[effectiveSegmentIndex]
            let startSample = Int64(startMarkerValue * Double(frames))
            let endSample = Int64(endMarkerValue * Double(frames))

            if startSample < endSample {
                 let velocityRange = velocityRanges[velocityRangeIndex]
                 segmentInfos.append((start: startSample, end: endSample, velocity: velocityRange))
                 print(" -> Preparing Segment \(effectiveSegmentIndex + 1) [\(startSample)-\(endSample)] for Vel [\(velocityRange.min)-\(velocityRange.max)]")
            } else {
                 print("Skipping zero-length segment \(effectiveSegmentIndex + 1) for velocity mapping.")
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