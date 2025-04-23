import SwiftUI
import AVFoundation
import AudioKit // Import the main AudioKit framework
import AudioKitUI // Import the UI components
// import AbletonSampler // Explicitly import the module if needed

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
    // --- NEW: Optional override for target note context ---
    let targetNoteOverride: Int? // If provided, restricts mapping options
    // ------------------------------------------------------

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
    // This state is less relevant if we hide the per-segment picker when targetNoteOverride is set
    @State private var selectedSegmentIndex: Int? = nil

    // --- State for Mapping ---
    // Use targetNoteOverride if available, otherwise default/allow selection
    @State private var targetMidiNote: Int // Needs initialization

    // --- Computed property for the full MIDI range (0-127) --- 
    private var availablePianoKeys: [PianoKey] {
        // Assuming viewModel.pianoKeys now holds the full 0-127 range.
        return viewModel.pianoKeys
    }
    private var availableMidiNoteRange: Range<Int> {
        // Full MIDI range
        return 0..<128 // Use 128 for exclusive upper bound (0...127)
    }

    // --- NEW: State for Dragging Markers ---
    @State private var draggedMarkerIndex: Int? = nil
    // Use GestureState for smooth updates during drag without complex state management
    @GestureState private var dragOffset: CGSize = .zero

    // --- NEW: Auto-Mapping State (Updated Defaults) --- 
    @State private var autoMapStartNote: Int = 24 // Default to C0 (MIDI 24)
    @State private var velocityMapTargetNote: Int = 60 // Default to C4 (MIDI 60)
    @State private var roundRobinTargetNote: Int = 60 // Default to C4 (MIDI 60)

    // --- NEW: Transient Detection State ---
    @State private var transientThreshold: Double = 0.1 // Default sensitivity (0.0 to 1.0)
    // Higher value = less sensitive (fewer markers), Lower value = more sensitive (more markers)

    // --- Computed Property: Number of Segments ---
    private var numberOfSegments: Int {
        markers.count + 1
    }

    // --- Initializer --- 
    init(audioFileURL: URL, targetNoteOverride: Int? = nil) {
        self.audioFileURL = audioFileURL
        self.targetNoteOverride = targetNoteOverride
        // Initialize targetMidiNote based on override or default
        self._targetMidiNote = State(initialValue: targetNoteOverride ?? 60) // Default C4 if no override
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

            // --- CONDITIONAL MAPPING CONTROLS --- 
            if targetNoteOverride == nil {
                // --- Show FULL controls if NO override --- 
                
                // REMOVED: Manual Segment Mapping UI (Picker and Assign Button)
                /*
                Text("Manual Segment Mapping").font(.headline)
                Picker("Select Segment", selection: $selectedSegmentIndex) {
                     Text("None").tag(nil as Int?)
                     ForEach(0..<numberOfSegments, id: \.self) { index in
                         Text("Segment \(index + 1)").tag(index as Int?)
                     }
                 }
                 .pickerStyle(.segmented)
                 .padding(.bottom, 5)

                if let segmentIndex = selectedSegmentIndex {
                    HStack {
                        Text("Map Segment \(segmentIndex + 1) to:")
                        Picker("Target MIDI Note", selection: $targetMidiNote) {
                            ForEach(availablePianoKeys) { key in Text("\(key.name) (\(key.id))").tag(key.id) }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 100).labelsHidden()
                        Spacer()
                        Button("Assign Segment") { assignSegmentToNote(segmentIndex: segmentIndex) } // <<< THIS CAUSED THE ERROR
                            .buttonStyle(.bordered)
                    }
                } else {
                    Text("Select a segment above to map it to a MIDI note.")
                        .font(.footnote).foregroundColor(.secondary).frame(height: 30)
                }
                
                Divider().padding(.vertical, 5)
                 */
                
                Text("Auto-Mapping (All Segments)").font(.headline)
                // Sequential Mapping Controls
                HStack {
                    Text("Map Sequentially starting at note:")
                    Picker("Start Note", selection: $autoMapStartNote) {
                         ForEach(availablePianoKeys) { key in Text("\(key.name) (\(key.id))").tag(key.id) }
                    }
                    .frame(width: 120).labelsHidden()
                    Spacer()
                    Button("Map Sequentially") {
                        // Pass viewModel explicitly
                        autoMapAllSegmentsSequentially(vm: self.viewModel)
                    }
                        .buttonStyle(.bordered)
                        .disabled(markers.isEmpty && numberOfSegments <= 1)
                }
                // Velocity Zones / Round Robin (targeting different notes)
                 HStack {
                     Text("Map to Velocity Zones on note:")
                     Picker("Target Note", selection: $targetMidiNote) { // Reuse targetMidiNote state
                          ForEach(availablePianoKeys) { key in Text("\(key.name) (\(key.id))").tag(key.id) }
                     }
                     .frame(width: 120).labelsHidden()
                     Spacer()
                     Button("Map Velocity Zones") {
                         // Pass viewModel explicitly
                         mapAllSegmentsAsVelocityZones(targetNote: targetMidiNote, vm: self.viewModel)
                     }
                         .buttonStyle(.bordered)
                         .disabled(markers.isEmpty && numberOfSegments <= 1)
                 }
                  HStack {
                     Text("Map as Round Robin on note:")
                     Picker("Target Note", selection: $targetMidiNote) { // Reuse targetMidiNote state
                          ForEach(availablePianoKeys) { key in Text("\(key.name) (\(key.id))").tag(key.id) }
                     }
                     .frame(width: 120).labelsHidden()
                     Spacer()
                     Button("Map Round Robin") {
                         // Pass viewModel explicitly (when implemented)
                         mapAllSegmentsAsRoundRobin(targetNote: targetMidiNote, vm: self.viewModel)
                     }
                         .buttonStyle(.bordered)
                         .disabled(markers.isEmpty && numberOfSegments <= 1)
                 }
                
            } else {
                 // --- Show RESTRICTED controls if override IS set --- 
                 Text("Map Segments to Note \(targetNoteOverride!)").font(.headline) // Show the target note
                 HStack {
                      Button("Map Segments as Velocity Zones") {
                          // Pass viewModel explicitly
                          mapAllSegmentsAsVelocityZones(targetNote: targetNoteOverride!, vm: self.viewModel)
                      }
                         .buttonStyle(.bordered)
                         .disabled(markers.isEmpty && numberOfSegments <= 1)
                      Spacer()
                      Button("Map Segments as Round Robin") {
                          // Pass viewModel explicitly (when implemented)
                          mapAllSegmentsAsRoundRobin(targetNote: targetNoteOverride!, vm: self.viewModel)
                      }
                         .buttonStyle(.bordered)
                         .disabled(markers.isEmpty && numberOfSegments <= 1)
                 }
                 .frame(maxWidth: .infinity) // Allow buttons to space out
             }
             // --------------------------------------

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
        .frame(minWidth: 550, minHeight: 580)
        .task {
            // Directly call the async function
            await loadAudioAndWaveform()
        }
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

    // MODIFIED: Accept ViewModel as parameter
    private func autoMapAllSegmentsSequentially(vm: SamplerViewModel) {
        guard targetNoteOverride == nil else { return } // Should only be callable in full editor mode
        let segments = calculateSegments() // Use corrected function
        guard !segments.isEmpty else {
             vm.showError("Cannot map: No segments defined (add markers first).")
             return
         }
        print("View: Requesting auto-mapping of \(segments.count) segments sequentially starting at \(autoMapStartNote)")
        // Use passed vm instance to call the *correct* ViewModel function
        vm.autoMapSegmentsSequentially(segments: segments, startNote: self.autoMapStartNote, sourceURL: self.audioFileURL)
        dismiss()
    }
    
    // MODIFIED: Accept ViewModel as parameter
    private func mapAllSegmentsAsVelocityZones(targetNote: Int, vm: SamplerViewModel) {
        let segments = calculateSegments() // Use corrected function
        guard !segments.isEmpty else {
             vm.showError("Cannot map: No segments defined (add markers first).")
             return
         }
        print("View: Requesting mapping of \(segments.count) segments as velocity zones to note \(targetNote)")
        // Use passed vm instance to call the *correct* ViewModel function
        vm.addSegmentsToNote(segments: segments, midiNote: targetNote, sourceURL: self.audioFileURL)
        dismiss()
    }
    
    // MODIFIED: Accept ViewModel as parameter
    private func mapAllSegmentsAsRoundRobin(targetNote: Int, vm: SamplerViewModel) {
        let segments = calculateSegments() // Use corrected function
        guard !segments.isEmpty else {
             vm.showError("Cannot map: No segments defined (add markers first).")
             return
         }
        print("View: Requesting mapping of \(segments.count) segments as round robin to note \(targetNote)")
        // Use passed vm instance to call the ViewModel function (when implemented)
        vm.mapSegmentsAsRoundRobin(segments: segments, midiNote: targetNote, sourceURL: self.audioFileURL)
        dismiss()
    }

    // --- CORRECTED: calculateSegments --- 
    /// Calculates the normalized start and end points (0.0 to 1.0) for each segment based on the sorted `markers` array.
    /// - Returns: An array of tuples `(start: Double, end: Double)`. Returns an empty array if audio not loaded or no segments possible.
    private func calculateSegments() -> [(start: Double, end: Double)] {
        // Requires audio to be loaded to determine segment count, though totalFrames isn't directly used here anymore
        guard let _ = audioFile, !isLoadingWaveform else {
            print("Warning: calculateSegments called before audio loaded.")
            return []
        }
        
        var segmentRanges: [(start: Double, end: Double)] = [] // Array to store results
        let sortedMarkers = markers.sorted() // Ensure markers are sorted (should already be)

        // Determine segment boundaries
        var lastMarkerPos: Double = 0.0
        for markerPos in sortedMarkers {
            // Ensure segment has positive length and positions are valid
            if markerPos > lastMarkerPos && markerPos <= 1.0 && lastMarkerPos >= 0.0 {
                segmentRanges.append((start: lastMarkerPos, end: markerPos))
            }
            lastMarkerPos = markerPos
        }

        // Add the last segment (from the last marker to the end)
        if lastMarkerPos < 1.0 && lastMarkerPos >= 0.0 { // Check lastMarkerPos validity
            segmentRanges.append((start: lastMarkerPos, end: 1.0))
        }
        
        // Handle the edge case of NO markers (results in one segment covering the whole file)
        if sortedMarkers.isEmpty {
            segmentRanges.append((start: 0.0, end: 1.0))
        }

        print("Calculated \(segmentRanges.count) segments: \(segmentRanges)")
        return segmentRanges
    }
    // -----------------------------------
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