import SwiftUI
import AVFoundation
import AudioKit // Import the main AudioKit framework
// import AudioKitUI // Import the UI components
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

// --- NEW: PreferenceKey for Scroll Offset ---
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        // Keep the latest reported offset
        value = nextValue()
    }
}
// -----------------------------------------

// --- UPDATED: Marker View with Draggable Handle ---
struct MarkerView: View {
    // Binding to indicate if this specific marker is being dragged
    // This can be used for visual feedback (e.g., changing color)
    @Binding var isBeingDragged: Bool
    // --- NEW: Add view height for proper marker line length ---
    let viewHeight: CGFloat

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
                .frame(width: 2, height: viewHeight) // Use passed height
                .opacity(0.7)
        }
        // Adjust tappable area height based on viewHeight
        .contentShape(Rectangle().size(width: 20, height: viewHeight + 12))
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
    // --- NEW: Store max RMS for auto-scaling ---
    @State private var maxRMSValue: Float = 0.001 // Avoid division by zero
    @State private var isLoadingWaveform = true
    
    // --- State for Markers & Segments ---
    @State private var markers: [Double] = [] // Sorted normalized positions (0.0-1.0)
    @State private var selectedSegmentIndex: Int? = nil
    
    // --- State for Mapping ---
    @State private var targetMidiNote: Int
    
    // --- UPDATED: State for transient tracking ---
    @State private var originalTransientIndices: [Int] = [] // Raw indices from last detection
    // --- NEW: Map from original transient index to current marker position ---
    @State private var markerOriginalIndexMap: [Int: Double] = [:] // [OriginalIndex: CurrentMarkerPosition]
    
    // --- NEW: State for Waveform Zoom and Pan ---
    @State private var amplitudeScale: CGFloat = 1.0 // Vertical scaling
    @State private var timeZoomScale: CGFloat = 1.0 // Horizontal zoom (1.0 = no zoom)
    @State private var scrollOffset: CGPoint = .zero // Current scroll position
    @State private var waveformViewID = UUID() // To force geometry reader update sometimes
    // ------------------------------------------
    
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
    // --- NEW: State for Transient Pre-detection Offset ---
    @State private var transientPreemptSamples: Int = 1 // Number of waveform samples to shift marker back
    
    // --- Computed Property: Number of Segments ---
    private var numberOfSegments: Int {
        // Use originalTransientIndices count to determine if transients *were* detected
        // If so, markers represent transient markers. Otherwise, they are manually placed.
        markers.count + 1
    }
    
    // --- NEW: Computed Property for total content width ---
    private var totalContentWidth: CGFloat {
        waveformWidth * timeZoomScale
    }
    // --------------------------------------------------
    
    // --- Initializer ---
    init(audioFileURL: URL, targetNoteOverride: Int? = nil) {
        self.audioFileURL = audioFileURL
        self.targetNoteOverride = targetNoteOverride
        // Initialize targetMidiNote based on override or default
        self._targetMidiNote = State(initialValue: targetNoteOverride ?? 60) // Default C4 if no override
    }
    
        var body: some View {
        VStack(spacing: 15) { // Main VStack for the whole view
            Text("Audio Segment Editor")
                .font(.title2)

            Text("Editing: \(audioFileURL.lastPathComponent)")
                .font(.caption)
                .lineLimit(1)

            // --- UPDATED: Waveform Display Area with Controls ---
            HStack(alignment: .center, spacing: 5) { // Use HStack for waveform + amplitude slider (Alignment is .center)
                VStack { // VStack for waveform + time zoom slider
                    GeometryReader { geometry in
                        // Update waveformWidth whenever geometry changes AND it's valid
                        let _ = DispatchQueue.main.async {
                            if self.waveformWidth != geometry.size.width && geometry.size.width > 0 {
                                self.waveformWidth = geometry.size.width
                                // print("Waveform Width updated via GeometryReader: \(self.waveformWidth)") // Optional debug
                            }
                        }

                        ScrollViewReader { scrollProxy in
                            ScrollView(.horizontal, showsIndicators: true) { // Always allow scroll gestures, disable based on zoom
                                ZStack(alignment: .leading) {
                                    // Background
                                    Color.secondary.opacity(0.4)

                                    // --- Waveform Canvas ---
                                    if isLoadingWaveform {
                                        ProgressView()
                                            .frame(width: geometry.size.width, height: geometry.size.height) // Center in visible area
                                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2) // Ensure it stays centered
                                    } else if !waveformRMSData.isEmpty && waveformWidth > 0 {
                                        // --- CUSTOM WAVEFORM DRAWING ---
                                        Canvas { context, size in
                                            drawWaveform(context: &context, size: size)
                                        }
                                        .frame(width: totalContentWidth, height: geometry.size.height) // Canvas size matches content
                                        .id("\(scrollOffset.x)-\(scrollOffset.y)") // Force redraw on scroll
                                        // --- END CUSTOM WAVEFORM DRAWING ---

                                        // --- UPDATED: Display Markers ---
                                        ForEach(markers, id: \.self) { markerPosition in
                                            let index = markers.firstIndex(of: markerPosition) ?? -1
                                            if index != -1 {
                                                let isDraggingThisMarker = (draggedMarkerIndex == index)
                                                let initialXPositionInContent = calculateMarkerXPositionInContent(markerValue: markerPosition)
                                                let currentXPositionInContent = isDraggingThisMarker ? initialXPositionInContent + dragOffset.width : initialXPositionInContent

                                                MarkerView(isBeingDragged: .constant(isDraggingThisMarker), viewHeight: geometry.size.height)
                                                    .position(x: currentXPositionInContent, y: geometry.size.height / 2)
                                                    .gesture(
                                                        DragGesture(minimumDistance: 1)
                                                            .updating($dragOffset) { value, state, _ in
                                                                state = value.translation
                                                                DispatchQueue.main.async {
                                                                    if self.draggedMarkerIndex == nil && index < self.markers.count {
                                                                        self.draggedMarkerIndex = index
                                                                    }
                                                                }
                                                            }
                                                            .onEnded { value in
                                                                if let validIndex = self.draggedMarkerIndex, validIndex < self.markers.count {
                                                                    finalizeMarkerDrag(index: validIndex, dragTranslation: value.translation)
                                                                }
                                                                self.draggedMarkerIndex = nil
                                                            }
                                                    )
                                                    .onTapGesture(count: 2) {
                                                        deleteMarker(at: index)
                                                    }
                                            } // end if index != -1
                                        } // end ForEach markers
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .overlay(Text("Could not load waveform").foregroundColor(.white))
                                            .frame(width: geometry.size.width, height: geometry.size.height) // Ensure error message fills visible area
                                    } // End waveform drawing conditions
                                } // End ZStack
                                .background(GeometryReader { geo in
                                    Color.clear.preference(key: ScrollOffsetPreferenceKey.self,
                                                           value: geo.frame(in: .named("scrollView")).origin)
                                })
                                .contentShape(Rectangle()) // Make tappable
                            } // End ScrollView
                            .coordinateSpace(name: "scrollView")
                            .scrollDisabled(timeZoomScale <= 1.0) // Disable scrolling if not zoomed
                            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
                                self.scrollOffset = newOffset
                                // print("Scroll Offset Updated via PrefKey: \(newOffset)") // Optional debug
                            }
                        } // End ScrollViewReader (NOTE: ScrollView ends inside this)
                    } // End GeometryReader (geometry)
                    // <<< NO frame/clipped modifier here on GeometryReader >>>

                    // --- Horizontal Time Zoom Slider (AFTER GeometryReader) ---
                    HStack {
                        Text("Zoom:")
                        Slider(value: $timeZoomScale, in: 1.0...20.0)
                        Text(String(format: "%.1fx", timeZoomScale))
                    }
                    .padding(.top, 5)
                    .disabled(isLoadingWaveform || waveformRMSData.isEmpty)
                    // ------------------------------------

                } // End VStack for waveform + time zoom
                .frame(height: 150) // <<< Frame applied to this VStack
                .clipped() // <<< Clip applied to this VStack

                // --- Vertical Amplitude Slider ---
                Slider(value: $amplitudeScale, in: 0.1...max(1.0, 50.0 / max(CGFloat(maxRMSValue), 0.01)))
                    .frame(width: 130, height: 20)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20, height: 150)
                    .padding(.leading, 5)
                    .disabled(isLoadingWaveform || waveformRMSData.isEmpty)
                // ----------------------------------
            } // End HStack for waveform area + amplitude slider
            // <<< NO .padding(.horizontal) here >>>
            // --------------------------------------------------

            // --- Marker Controls ---
            HStack {
                Button("Clear All Markers") {
                    markers.removeAll()
                    originalTransientIndices = []
                    markerOriginalIndexMap = [:]
                    selectedSegmentIndex = nil
                }
                .disabled(markers.isEmpty)

                // Spacer() // Optional: Removed earlier, keep removed? Or add back for layout? Let's keep it removed for now.

                // --- UPDATED: Transient Detection Controls ---
                VStack(alignment: .trailing, spacing: 5) {
                    HStack {
                        Text("Sensitivity:")
                        Slider(value: $transientThreshold, in: 0.01...1.0)
                            .frame(width: 100)
                    }
                    .font(.caption)

                    HStack {
                        Text("Pre-detect Samples:")
                        Stepper("\(transientPreemptSamples)", value: $transientPreemptSamples, in: 0...20)
                    }
                    .font(.caption)

                    Button("Detect Transients") {
                        detectAndSetTransients()
                    }
                    .disabled(isLoadingWaveform || waveformRMSData.isEmpty)
                } // End Transient VStack
            } // End Marker Controls HStack
            .padding(.horizontal) // Add horizontal padding here for the controls section

            // --- Segment Information & Mapping ---
            Text(audioInfo)
                .font(.footnote)

            Text("Segments Defined: \(numberOfSegments)")
                .font(.footnote)

            // --- DEBUG: Show Scroll Offset ---
            Text("Scroll Offset: (\(String(format: "%.1f", scrollOffset.x)), \(String(format: "%.1f", scrollOffset.y)))")
                .font(.caption)
                .foregroundColor(.orange)
            // --- END DEBUG ---

            // --- CONDITIONAL MAPPING CONTROLS ---
            if targetNoteOverride == nil {
                Text("Auto-Mapping (All Segments)").font(.headline)
                HStack {
                    Text("Map Sequentially starting at note:")
                    Picker("Start Note", selection: $autoMapStartNote) {
                        ForEach(availablePianoKeys) { key in Text("\(key.name) (\(key.id))").tag(key.id) }
                    }
                    .frame(width: 120).labelsHidden()
                    Spacer()
                    Button("Map Sequentially") {
                        autoMapAllSegmentsSequentially(vm: self.viewModel)
                    }
                    .buttonStyle(.bordered)
                    .disabled(markers.isEmpty && numberOfSegments <= 1)
                }
                HStack {
                    Text("Map to Velocity Zones on note:")
                    Picker("Target Note", selection: $targetMidiNote) {
                        ForEach(availablePianoKeys) { key in Text("\(key.name) (\(key.id))").tag(key.id) }
                    }
                    .frame(width: 120).labelsHidden()
                    Spacer()
                    Button("Map Velocity Zones") {
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
                        mapAllSegmentsAsRoundRobin(targetNote: targetMidiNote, vm: self.viewModel)
                    }
                    .buttonStyle(.bordered)
                    .disabled(markers.isEmpty && numberOfSegments <= 1)
                }

            } else { // Restricted Controls
                Text("Map Segments to Note \(targetNoteOverride!)").font(.headline)
                HStack {
                    Button("Map Segments as Velocity Zones") {
                        mapAllSegmentsAsVelocityZones(targetNote: targetNoteOverride!, vm: self.viewModel)
                    }
                    .buttonStyle(.bordered)
                    .disabled(markers.isEmpty && numberOfSegments <= 1)
                    Spacer()
                    Button("Map Segments as Round Robin") {
                        mapAllSegmentsAsRoundRobin(targetNote: targetNoteOverride!, vm: self.viewModel)
                    }
                    .buttonStyle(.bordered)
                    .disabled(markers.isEmpty && numberOfSegments <= 1)
                }
                .frame(maxWidth: .infinity)
            } // End Conditional Mapping Controls

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

            Spacer() // <<< FINAL SPACER to push content up within the frame

        } // End Main VStack
        .padding() // Apply overall padding
        // --- ADJUSTED FRAME ---
        .frame(minWidth: 600, minHeight: 650) // Apply frame to main VStack
        .task {
            await loadAudioAndWaveform()
        }
        // --- UPDATED: onChange handlers ---
        .onChange(of: transientPreemptSamples) { oldValue, newValue in
            guard !markerOriginalIndexMap.isEmpty, !waveformRMSData.isEmpty, waveformWidth > 0 else { return }
            print("Pre-detect samples changed to \(newValue). Recalculating mapped marker positions.")
            updateMappedMarkerPositions(preempt: newValue)
        }
        .onChange(of: transientThreshold) { oldValue, newValue in
            guard !isLoadingWaveform && !waveformRMSData.isEmpty else {
                print("Skipping auto transient detection: Waveform not ready.")
                return
            }
            print("Transient sensitivity slider changed to \(newValue). Re-detecting transients.")
            detectAndSetTransients()
        }
    } // End body
    // --- Helper Functions ---

    // --- UPDATED: Use async/await and extract waveform data ---
    @MainActor
    private func loadAudioAndWaveform() async {
        print("Loading audio data and waveform for: \(audioFileURL.path)")
        // Reset state
        isLoadingWaveform = true
        waveformRMSData = []
        markers = []
        markerOriginalIndexMap = [:]
        audioFile = nil
        totalFrames = nil
        audioInfo = "Loading..."
        originalTransientIndices = []
        // --- RESET NEW STATE ---
        amplitudeScale = 1.0
        timeZoomScale = 1.0
        scrollOffset = .zero
        maxRMSValue = 0.001
        waveformWidth = 0 // Reset width until GeometryReader provides it
        waveformViewID = UUID() // Force geometry update if needed
        // ---------------------

        do {
            let file = try AVAudioFile(forReading: audioFileURL)
            let format = file.processingFormat
            // Use file.length which is AVAudioFramePosition (Int64)
            let frameCountInt64 = file.length
            let frameCount = Int(frameCountInt64) // Convert to Int for array indexing, check potential overflow for huge files if necessary

            // Basic info update (on main thread initially)
            self.audioFile = file
            self.totalFrames = frameCountInt64 // Store original Int64
            let duration = Double(frameCount) / format.sampleRate
            self.audioInfo = String(format: "Duration: %.2f s | Rate: %.0f Hz | Frames: %lld",
                                    duration, format.sampleRate, frameCountInt64)
            print("Audio info loaded. Frames: \(frameCount), Sample Rate: \(format.sampleRate)")

            // Read audio data into a buffer
            // Ensure frameCapacity matches the actual frame count
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frameCountInt64)) else {
                throw NSError(domain: "AudioLoadError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create buffer"])
            }
            // Read the entire file into the buffer
            try file.read(into: buffer)
            // Use the buffer's actual frame length after reading, should match frameCount
            let frameLength = Int(buffer.frameLength)
             guard frameLength == frameCount else {
                  print("Warning: Buffer frame length (\(frameLength)) does not match file frame count (\(frameCount)). Using buffer length.")
                  // Potentially throw an error or adjust frameCount based on buffer length
                  // For now, we'll proceed using frameLength derived from the buffer.
                  // frameCount = frameLength // If we decide to trust the buffer length more
                  throw NSError(domain: "AudioLoadError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Mismatch between file frame count and buffer frame length after reading."])
             }


            // --- Copy Audio Data for Background Processing ---
            guard let floatChannelData = buffer.floatChannelData else {
                 throw NSError(domain: "AudioLoadError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not get float channel data"])
            }
            // Assuming mono or taking the first channel
            let channelPtr = floatChannelData[0]
            // Create a Swift array copy of the data
            // Ensure frameLength is used for the count
            let audioDataCopy = [Float](UnsafeBufferPointer(start: channelPtr, count: frameLength))
            print("Copied \(audioDataCopy.count) audio samples for background processing.")
            // --- End Copy ---


            // Calculate RMS display samples
            let samplesPerPixel = 1024 // Process N source samples for each display point
            // Use frameLength (derived from buffer) for calculation consistency
            let displaySamplesCount = max(1, frameLength / samplesPerPixel)
            var rmsSamples = [Float](repeating: 0.0, count: displaySamplesCount) // Pre-allocate


            // --- RMS Calculation on Background Thread using Copied Data ---
            // Capture the copied array, not the buffer or pointer
            DispatchQueue.global(qos: .userInitiated).async { [audioDataCopy] in
                // totalFramesInBuffer now refers to the count of the copied array
                let totalFramesInBuffer = audioDataCopy.count

                for i in 0..<displaySamplesCount {
                    let startFrame = i * samplesPerPixel
                    // Use totalFramesInBuffer for bounds checking
                    let endFrame = min(startFrame + samplesPerPixel, totalFramesInBuffer)
                    let frameCountInBlock = endFrame - startFrame

                    if frameCountInBlock > 0 {
                        var sumOfSquares: Float = 0.0
                        // Access samples from the copied array
                        for j in startFrame..<endFrame {
                            // Index safety check against the copied array's bounds
                            guard j >= 0 && j < totalFramesInBuffer else {
                                print("Error: Invalid index \(j) accessed in RMS calculation loop (copied data). Max: \(totalFramesInBuffer)")
                                continue
                            }
                            let sample = audioDataCopy[j] // Read from the copy
                            sumOfSquares += sample * sample
                        }
                        // Calculate RMS for the block
                        let meanSquare = sumOfSquares / Float(frameCountInBlock)
                        rmsSamples[i] = sqrt(meanSquare)
                    } else {
                        rmsSamples[i] = 0.0
                    }
                }

                // --- Update State back on Main Thread ---
                DispatchQueue.main.async {
                    // No need for [weak self] guard check here as the outer function is @MainActor
                    // and the DispatchQueue.main.async ensures this runs on the main thread.
                    // If the view is gone, setting state does nothing harmful.

                    print("Waveform RMS data extracted from copy. Display samples: \(rmsSamples.count)")

                    // Only update UI state if this task is still relevant (isLoadingWaveform is true)
                    if self.isLoadingWaveform {
                        self.waveformRMSData = rmsSamples
                        self.isLoadingWaveform = false

                        // --- AUTO AMPLITUDE SCALING ---
                        self.maxRMSValue = rmsSamples.max() ?? 0.001 // Store max RMS
                        let targetAmplitude: CGFloat = 0.75 // Target 75% of height
                        // Calculate scale needed to make maxRMSValue hit targetAmplitude
                        let requiredScale = (self.maxRMSValue > 0) ? (targetAmplitude / CGFloat(self.maxRMSValue)) : 1.0
                        // Clamp scale to prevent excessively large values for silence
                        self.amplitudeScale = max(0.1, min(requiredScale, 50.0)) // Example clamp range
                        print("Auto-scaling waveform. Max RMS: \(self.maxRMSValue), Initial Amplitude Scale: \(self.amplitudeScale)")
                        // -----------------------------

                        // --- Recalculation logic on load completion ---
                        if self.waveformWidth > 0 && !self.markerOriginalIndexMap.isEmpty {
                            print("Waveform loaded, width known. Re-applying pre-detect offset to mapped markers.")
                            self.updateMappedMarkerPositions(preempt: self.transientPreemptSamples)
                        }
                        print("Waveform loading complete. isLoadingWaveform set to false.")
                    } else {
                         print("Skipping UI update for waveform data as isLoadingWaveform is false.")
                    }
                }
            } // End background calculation

        } catch {
            // Ensure UI updates from errors happen on main thread
            DispatchQueue.main.async {
                let errorMsg = "Error loading audio/waveform: \(error.localizedDescription)"
                print(errorMsg)
                self.audioInfo = errorMsg
                self.isLoadingWaveform = false // Ensure loading stops on error
                self.waveformRMSData = []
                self.markerOriginalIndexMap = [:] // Clear map on error
                self.originalTransientIndices = []
                self.markers = []
                self.viewModel.showError("Failed to load audio file: \(error.localizedDescription)")
            }
        }
    }

    // --- UPDATED: addMarker (Considers Zoom & Scroll) ---
    private func addMarker(at point: CGPoint, visibleWidth: CGFloat) {
        guard waveformWidth > 0, totalContentWidth > 0 else { return }

        // Point.x is relative to the VISIBLE frame.
        // scrollOffset.x is the negative offset of the content origin within the visible frame.
        // Calculate the tap position relative to the START of the ZStack content.
        let xInContent = point.x - scrollOffset.x // Correct for scroll

        // Normalize this position relative to the TOTAL content width
        let normalizedPosition = max(0.0, min(1.0, xInContent / totalContentWidth))

        // Calculate the equivalent X position in the UNZOOMED view for distance check
        let equivalentUnzoomedX = normalizedPosition * waveformWidth
        let minPixelDistance: CGFloat = 2.0 // Minimum distance in VISIBLE pixels

        // Check distance against existing markers based on their *current* unzoomed positions
        if !markers.contains(where: {
            let existingMarkerUnzoomedX = calculateMarkerXPositionInContent(markerValue: $0) / timeZoomScale
            return abs(existingMarkerUnzoomedX - equivalentUnzoomedX) < minPixelDistance
        }) {
            markers.append(normalizedPosition)
            markers.sort() // Keep markers sorted by position
            // --- Adding a manual marker does NOT affect the map ---
            print("Added manual marker at normalized position: \(normalizedPosition) (Tap Point: \(point), Scroll: \(scrollOffset), xInContent: \(xInContent))")
        } else {
            print("Marker position \(normalizedPosition) too close to existing marker. Ignoring.")
        }
    }

    // --- UPDATED: Calculates X position within the TOTAL ZOOMED CONTENT ---
    private func calculateMarkerXPositionInContent(markerValue: Double) -> CGFloat {
        guard waveformWidth > 0 else { return 0 }
        // Clamp normalized value just in case
        let clampedValue = max(0.0, min(1.0, markerValue))
        // Position is relative to the total width of the scrollable content
        return clampedValue * totalContentWidth
    }

    // --- UPDATED: finalizeMarkerDrag (Considers Zoom) ---
    private func finalizeMarkerDrag(index: Int, dragTranslation: CGSize) {
        guard index >= 0 && index < markers.count else { return }
        guard waveformWidth > 0, totalContentWidth > 0 else { return }

        let originalValue = markers[index] // Original normalized position
        // Calculate the marker's X position within the content *before* the drag ended
        let originalXInContent = calculateMarkerXPositionInContent(markerValue: originalValue)

        // The drag translation is in the coordinate space of the visible frame,
        // which matches the coordinate space of the zoomed content when dragging.
        let newXInContent = originalXInContent + dragTranslation.width

        // Clamp the new position within the bounds of the total content width
        let clampedNewXInContent = max(0, min(totalContentWidth, newXInContent))

        // Convert the new content position back to a normalized value (0-1)
        let newNormalizedValue = clampedNewXInContent / totalContentWidth

        // Update the marker's normalized position in the array
        markers[index] = newNormalizedValue

        // --- Map removal logic (unchanged, operates on normalized values) ---
        if let originalIndexKey = markerOriginalIndexMap.first(where: { $1 == originalValue })?.key {
            markerOriginalIndexMap.removeValue(forKey: originalIndexKey)
            print("Removed mapping for original transient index \(originalIndexKey) due to manual move.")
        }
        // -------------------------------------------------------------------

        // Re-sort the array after modification
        markers.sort()

        print("Moved marker \(index) to normalized position: \(newNormalizedValue) (Final X in content: \(clampedNewXInContent))")
    }

    // --- UPDATED: Transient Detection Logic ---

    /// Detects transients, stores original indices, calculates initial positions, and populates the map.
    private func detectAndSetTransients() {
        guard !waveformRMSData.isEmpty, waveformWidth > 0 else {
            print("Cannot detect transients: Waveform data or width not available.")
            viewModel.showError("Waveform not loaded or layout not ready.")
            return
        }

        let internalThreshold = 1.0 - transientThreshold
        print("Detecting transients with internal threshold: \(internalThreshold)")

        // 1. Find original transient indices
        let detectedIndices = findTransients(in: waveformRMSData, threshold: Float(internalThreshold))
        self.originalTransientIndices = detectedIndices // Store the raw indices
        print("Detected \(detectedIndices.count) raw transient indices.")

        // 2. Calculate initial marker positions and populate the map
        let initialPositionsResult = calculateInitialMarkerPositionsAndMap(
            indices: detectedIndices,
            preempt: self.transientPreemptSamples,
            dataCount: waveformRMSData.count
        )

        self.markers = initialPositionsResult.positions.sorted() // Set sorted positions
        self.markerOriginalIndexMap = initialPositionsResult.map // Set the map

        print("Set \(markers.count) markers based on detected transients. Populated map with \(markerOriginalIndexMap.count) entries.")
        self.selectedSegmentIndex = nil
    }

    /// Analyzes waveform data (RMS values) to find indices where transients likely start.
    /// - Parameter data: Array of RMS or similar amplitude values.
    /// - Parameter threshold: Sensitivity threshold (normalized 0.0 to 1.0, derived from slider). Lower value detects more transients.
    /// - Returns: An array of integer indices corresponding to the *start* of detected transients in the `data` array.
    private func findTransients(in data: [Float], threshold: Float) -> [Int] {
        guard data.count > 1 else { return [] }

        var transientIndices: [Int] = []
        let dataCount = data.count
        // Minimum energy threshold to avoid detecting transients in near silence
        let minEnergyThreshold: Float = 0.005 // Adjust based on expected signal levels

        // Calculate differences between consecutive RMS values (potential onsets)
        // Using `difference(from:)` might be slightly more Swift-idiomatic if performance allows
        var differences: [Float] = []
        differences.reserveCapacity(dataCount - 1)
        for i in 0..<(dataCount - 1) {
            // We are looking for increases, so don't take abs() here?
            // Let's stick to abs() for general change detection for now.
            let diff = abs(data[i+1] - data[i])
            differences.append(diff)
        }

        // Find the maximum difference for normalization (handle potential division by zero)
        guard let maxDifference = differences.max(), maxDifference > Float.ulpOfOne else {
            print("No significant differences found in RMS data (maxDifference: \(differences.max() ?? -1)).")
            return [] // No differences to analyze or max difference is effectively zero
        }

        print("Max RMS difference: \(maxDifference)")

        // Detect peaks in the differences that exceed the threshold
        for i in 0..<differences.count {
            // Normalize the difference to compare against the threshold
            let normalizedDiff = differences[i] / maxDifference

            // Check conditions:
            // 1. Normalized difference exceeds the threshold
            // 2. Energy level at the *next* point (i+1) is above minimum (transient leads into sound)
            if normalizedDiff > threshold && data[i+1] > minEnergyThreshold {

                // Transient detected *starting* at index i (the rise begins here)
                let detectedIndex = i

                // Simple debounce: check distance from the last added index
                // This prevents clustering markers too closely based on RMS fluctuations.
                let minIndexDistance: Int = 2 // Minimum distance in RMS samples (adjust as needed)
                if let lastIndex = transientIndices.last {
                    if (detectedIndex - lastIndex) < minIndexDistance {
                        // print("Skipping transient index \(detectedIndex) too close to \(lastIndex)")
                        continue // Skip if too close
                    }
                }
                transientIndices.append(detectedIndex)
                 // print("Transient index detected at: \(detectedIndex), NormDiff: \(normalizedDiff)")
            }
        }

        // Indices are found in order, no sorting needed here.
        return transientIndices
    }

    // --- NEW HELPER: Calculates initial positions AND map from indices ---
    /// Calculates normalized marker positions and creates a map from original index to position.
    private func calculateInitialMarkerPositionsAndMap(indices: [Int], preempt: Int, dataCount: Int) -> (positions: [Double], map: [Int: Double]) {
        guard dataCount > 1 else { return ([], [:]) }
        let nonNegativePreempt = max(0, preempt)
        var calculatedPositions: [Double] = []
        var indexToPositionMap: [Int: Double] = [:]
        calculatedPositions.reserveCapacity(indices.count)
        indexToPositionMap.reserveCapacity(indices.count)

        let normalizationFactor = Double(dataCount - 1)
        guard normalizationFactor > 0 else { return ([], [:]) } // Avoid division by zero

        for index in indices {
            let adjustedIndex = max(0, index - nonNegativePreempt)
            let normalizedPosition = Double(adjustedIndex) / normalizationFactor
            let finalPosition = max(0.0, min(1.0, normalizedPosition))

            // Simple check to avoid near-duplicate positions causing issues later, though map prevents exact duplicates
            let minSeparation = 1e-9 // Very small value
            if !calculatedPositions.contains(where: { abs($0 - finalPosition) < minSeparation }) {
                 calculatedPositions.append(finalPosition)
                 indexToPositionMap[index] = finalPosition // Map original index to this position
            } else {
                 print("Warning: Skipping calculated position \(finalPosition) for index \(index) as it's too close to an existing one.")
            }
        }
        // Positions will be sorted when assigned to self.markers
        return (calculatedPositions, indexToPositionMap)
    }

    // --- NEW HELPER: Updates positions of mapped markers based on pre-detect ---
    /// Iterates through the current markers, updating positions for those mapped to original transients.
    private func updateMappedMarkerPositions(preempt: Int) {
        guard !markerOriginalIndexMap.isEmpty, !waveformRMSData.isEmpty, waveformWidth > 0, waveformRMSData.count > 1 else {
             print("Cannot update mapped markers: Map empty or data/layout not ready.")
             return
         }

        let dataCount = waveformRMSData.count
        let nonNegativePreempt = max(0, preempt)
        let normalizationFactor = Double(dataCount - 1)
        guard normalizationFactor > 0 else { return } // Avoid division by zero

        var updatedMarkers: [Double] = []
        var updatedMap: [Int: Double] = [:]
        updatedMarkers.reserveCapacity(markers.count)
        updatedMap.reserveCapacity(markerOriginalIndexMap.count)

        let currentMappedOriginalIndices = Set(markerOriginalIndexMap.keys)

        for currentMarkerPosition in markers {
            // Find the original index associated with this *current* marker position
            if let originalIndex = markerOriginalIndexMap.first(where: { $1 == currentMarkerPosition })?.key {
                 // This marker IS currently mapped to an original transient. Recalculate its position.
                 let adjustedIndex = max(0, originalIndex - nonNegativePreempt)
                 let normalizedPosition = Double(adjustedIndex) / normalizationFactor
                 let newPosition = max(0.0, min(1.0, normalizedPosition))

                 // Add the *new* position to the updated list
                 // Avoid adding near-duplicates that might arise from calculation
                 let minSeparation = 1e-9
                 if !updatedMarkers.contains(where: { abs($0 - newPosition) < minSeparation }) {
                     updatedMarkers.append(newPosition)
                     // Update the map with the new position for this original index
                     updatedMap[originalIndex] = newPosition
                 } else {
                     print("Warning: Skipping updated position \(newPosition) for original index \(originalIndex) - too close to another.")
                     // Need to decide if we keep the *old* position or just skip. Skipping seems safer.
                 }

            } else {
                // This marker is manual (not in the map's values). Keep its position.
                 updatedMarkers.append(currentMarkerPosition)
            }
        }

        // Replace the state with the updated values
        self.markers = updatedMarkers.sorted()
        self.markerOriginalIndexMap = updatedMap

        print("Updated positions for \(updatedMap.count) mapped markers based on pre-detect \(preempt). Total markers: \(self.markers.count).")
    }

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
    /// Handles the requirement to skip the segment from 0 to the first marker, unless the first marker is at 0.
    /// - Returns: An array of tuples `(start: Double, end: Double)`. Returns an empty array if audio not loaded or no segments possible.
    private func calculateSegments() -> [(start: Double, end: Double)] {
        // Requires audio to be loaded to define segments relative to the file duration
        guard audioFile != nil, !isLoadingWaveform else {
            print("Warning: calculateSegments called before audio loaded or while loading.")
            return []
        }

        var segmentRanges: [(start: Double, end: Double)] = [] // Array to store results
        let sortedMarkers = markers.sorted()

        // --- NEW LOGIC: Determine the starting point and which markers to iterate ---
        var lastMarkerPos: Double = 0.0
        var startIndexForLoop = 0 // Index of the first marker to use for the *end* of a segment

        if let firstMarker = sortedMarkers.first {
            if firstMarker > 0.0 {
                // First marker is NOT at the beginning. Start the first segment *at* the first marker.
                lastMarkerPos = firstMarker
                // The loop should start processing from the second marker (index 1)
                // because the first marker defines the start of the *first* segment.
                startIndexForLoop = 1
                print("calculateSegments: First marker at \(firstMarker), starting first segment there. Loop starts at index 1.")
            } else {
                // First marker is at 0.0. Start the first segment at 0.0 (standard behavior).
                lastMarkerPos = 0.0
                startIndexForLoop = 0 // Loop starts processing from the first marker (index 0)
                print("calculateSegments: First marker at 0.0, starting first segment at 0.0. Loop starts at index 0.")
            }
        } else {
            // No markers exist. Handle this case after the loop.
             print("calculateSegments: No markers found.")
        }
        // --- END NEW LOGIC ---


        // --- MODIFIED LOOP: Iterate from the determined start index ---
        if startIndexForLoop < sortedMarkers.count { // Check if there are markers to process in the loop
             for i in startIndexForLoop..<sortedMarkers.count {
                let markerPos = sortedMarkers[i]
                // Ensure segment has positive length and positions are valid [0.0, 1.0]
                // Clamp values just in case.
                let clampedStart = max(0.0, min(1.0, lastMarkerPos))
                let clampedEnd = max(0.0, min(1.0, markerPos))

                if clampedEnd > clampedStart { // Segment must have a non-zero duration
                    segmentRanges.append((start: clampedStart, end: clampedEnd))
                } else if clampedEnd < clampedStart {
                    print("Warning: Invalid segment order detected in calculateSegments. Start: \(clampedStart), End: \(clampedEnd)")
                } // else: if clampedEnd == clampedStart, segment has zero length, ignore.

                lastMarkerPos = markerPos // Use the original markerPos for the next iteration's start
            }
        } else if !sortedMarkers.isEmpty && startIndexForLoop == 1 {
             // Special case: Only ONE marker exists, and it was > 0.0.
             // The loop didn't run, but we need the segment from that marker to the end.
             // lastMarkerPos is already correctly set to the first marker's position.
             print("calculateSegments: Only one marker > 0.0 found. Will create segment from marker to end.")
        }
        // --- END MODIFIED LOOP ---


        // Add the last segment (from the position of the last processed marker to the end of the file)
        // This logic works correctly regardless of whether the loop ran or how `lastMarkerPos` was initialized.
        let clampedLastMarkerPos = max(0.0, min(1.0, lastMarkerPos))
        if clampedLastMarkerPos < 1.0 {
            segmentRanges.append((start: clampedLastMarkerPos, end: 1.0))
            print("calculateSegments: Added final segment from \(clampedLastMarkerPos) to 1.0")
        } else {
             print("calculateSegments: Final segment skipped (last marker position >= 1.0). Position: \(clampedLastMarkerPos)")
        }


        // Handle the edge case of NO markers: results in one segment covering the whole file
        // This needs to be handled *after* the main logic, only if segmentRanges is still empty.
        if sortedMarkers.isEmpty && segmentRanges.isEmpty {
            // Ensure audio is loaded before adding the full segment
            if audioFile != nil {
                 segmentRanges.append((start: 0.0, end: 1.0))
                 print("calculateSegments: No markers found, created single segment for full file (0.0 to 1.0).")
            } else {
                 print("Warning: calculateSegments - No markers and no audioFile, cannot create full segment.")
            }
        } else if !sortedMarkers.isEmpty && segmentRanges.isEmpty {
             // This might happen if markers are placed in a way that results in no valid segments (e.g., all markers at the same position > 0).
             print("Warning: calculateSegments - Markers exist, but no valid segments were generated.")
        }


        print("Calculated \(segmentRanges.count) segments based on current markers: \(segmentRanges)")
        return segmentRanges
    }
    // -----------------------------------

    // --- NEW: Function to Delete a Marker ---
    private func deleteMarker(at index: Int) {
        guard index >= 0 && index < markers.count else {
            print("Error: Invalid index \(index) for deleteMarker. Markers count: \(markers.count)")
            return
        }
        let deletedValue = markers[index] // Get position being deleted
        markers.remove(at: index) // Remove from visual markers array

        // Check if this deleted position corresponds to an original transient in the map
        if let originalIndexKey = markerOriginalIndexMap.first(where: { $1 == deletedValue })?.key {
            markerOriginalIndexMap.removeValue(forKey: originalIndexKey) // Remove the mapping
            print("Removed mapping for original transient index \(originalIndexKey) due to deletion.")
            // DO NOT remove from originalTransientIndices here - the index itself might be reused if detection runs again.
        } else {
             print("Deleted manual marker (position: \(deletedValue)). No transient mapping to remove.")
        }

        print("Deleted marker at index \(index). Markers count: \(markers.count). Mapped transients count: \(markerOriginalIndexMap.count)")
        selectedSegmentIndex = nil
    }
    // --- END NEW ---

    // --- NEW: Waveform Drawing Function (Simplified) ---
    private func drawWaveform(context: inout GraphicsContext, size: CGSize) {
        // --- GUARD CHECKS ---
        // Ensure we have data, valid dimensions, and a positive total content width
        guard !waveformRMSData.isEmpty, size.width > 0, size.height > 0, totalContentWidth > 0 else {
            // Optionally draw a placeholder line or do nothing if conditions aren't met
             if size.height > 0 {
                  var placeholderPath = Path()
                  placeholderPath.move(to: CGPoint(x: 0, y: size.height / 2))
                  placeholderPath.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                  context.stroke(placeholderPath, with: .color(.gray), lineWidth: 1)
             }
            print("DrawWaveform: Skipping draw - Conditions not met (Data empty: \\(!waveformRMSData.isEmpty), Size: \\(size), TotalContentWidth: \\(totalContentWidth))")
            return
        }

        let halfHeight = size.height / 2
        // canvasContentWidth represents the total width the waveform should occupy (zoomed)
        let canvasContentWidth = size.width
        let dataCount = waveformRMSData.count

        // --- Check if data is drawable ---
        guard dataCount > 1 else {
            // Draw a flat line if only one data point exists
            var flatLinePath = Path()
            flatLinePath.move(to: CGPoint(x: 0, y: halfHeight))
            flatLinePath.addLine(to: CGPoint(x: canvasContentWidth, y: halfHeight))
            context.stroke(flatLinePath, with: .color(.accentColor), lineWidth: 1)
            print("DrawWaveform: Drawing flat line - Only \\(dataCount) data point(s).")
            return
        }

        // Factor for normalizing index to a 0.0-1.0 range
        let normalizationFactor = Double(dataCount - 1)
        // Avoid division by zero if somehow dataCount is 1 (though guarded above)
        guard normalizationFactor > 0 else {
             print("DrawWaveform: Skipping draw - Invalid normalizationFactor.")
             return
        }

        // --- DEBUG LOGGING (Optional - keep if needed) ---
        // print("DrawWaveform - Drawing full path. Size: \\(size), DataCount: \\(dataCount), AmplitudeScale: \\(amplitudeScale)")
        // --------------------------------------------------

        // --- BUILD THE WAVEFORM PATH ---
        // Create the path by iterating through *all* RMS data points.
        let path = Path { p in
            var hasMoved = false // Ensure initial move happens only once

            for i in 0..<dataCount {
                // Calculate the normalized position (0.0 to 1.0) for the current data point
                let normalizedX = Double(i) / normalizationFactor

                // Calculate the absolute X position within the full canvas width
                let xPosition = normalizedX * canvasContentWidth

                // Get the RMS value and apply vertical scaling
                let rmsValue = CGFloat(waveformRMSData[i])
                let scaledAmplitude = rmsValue * amplitudeScale

                // Calculate the top and bottom Y coordinates for the vertical line segment
                // Clamp to the bounds of the drawing area (0 to size.height)
                let yTop = max(0, halfHeight - (scaledAmplitude * halfHeight))
                let yBottom = min(size.height, halfHeight + (scaledAmplitude * halfHeight))

                // Draw the vertical line segment for this point
                if !hasMoved {
                    // For the first point, move to the top Y position
                    p.move(to: CGPoint(x: xPosition, y: yTop))
                    hasMoved = true
                } else {
                    // For subsequent points, draw a line to the new top Y position
                    // This connects the top envelope shape
                    p.addLine(to: CGPoint(x: xPosition, y: yTop))
                }
                // Draw the vertical line down to the bottom Y position
                p.addLine(to: CGPoint(x: xPosition, y: yBottom))
                // Move back to the top position to prepare for the next segment's top line
                // This ensures the top envelope connects correctly without drawing diagonal lines across the gap.
                p.addLine(to: CGPoint(x: xPosition, y: yTop))
            }
             // Optional: Add a final line to the middle Y at the end if needed for visual closure,
             // but the vertical line drawing method above should suffice.
             // if let lastX = (0..<dataCount).last.map({ Double($0) / normalizationFactor * canvasContentWidth }) {
             //      p.addLine(to: CGPoint(x: lastX, y: halfHeight))
             // }
        }

        // --- STROKE THE PATH ---
        // Stroke the completed path onto the GraphicsContext.
        // The context, being part of the Canvas within the ScrollView,
        // should automatically handle clipping the path to the currently visible area.
        context.stroke(path, with: .color(.accentColor), lineWidth: 1)
    }
    // --- END Simplified Waveform Drawing ---
}

// --- Preview ---
struct AudioSegmentEditorView_Previews: PreviewProvider {
    static var previews: some View {
        // --- Use a known system sound or provide a placeholder ---
        // Attempt to load a common system sound as a fallback
        let defaultURL = URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")
        // Try to load a test sound from the bundle first
        let dummyURL = Bundle.main.url(forResource: "TestSound", withExtension: "wav") ?? defaultURL

        // Create a dummy ViewModel for the preview
        let dummyViewModel = SamplerViewModel()

        return AudioSegmentEditorView(audioFileURL: dummyURL)
            .environmentObject(dummyViewModel)
            .padding() // Add some padding around the preview
            .previewLayout(.sizeThatFits) // Fit the content size
            .background(Color(NSColor.windowBackgroundColor)) // Use system background for context
            .eraseToAnyView() // Type erasure helper
    }
}

// Helper to erase type for preview
extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
}
