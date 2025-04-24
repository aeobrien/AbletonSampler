// AbletonSampler/AbletonSampler/AudioSegmentEditorView.swift
import SwiftUI
import AVFoundation
import AudioKit // Import the main AudioKit framework
// import AudioKitUI // No longer needed directly here

// --- Marker View (UPDATED) ---
struct MarkerView: View {
    @Binding var isBeingDragged: Bool
    let viewHeight: CGFloat // NEW: Pass height dynamically

    var body: some View {
        VStack(spacing: 0) {
            // Draggable Handle (Flag)
            Circle()
                .fill(isBeingDragged ? Color.yellow : Color.red) // Highlight when dragged
                .frame(width: 12, height: 12)
                .shadow(radius: 2)
                .padding(.bottom, -1) // Overlap slightly with the line

            // Marker Line (Uses dynamic height)
            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: viewHeight) // Use passed height
                .opacity(0.7)
        }
        // Adjust tappable area based on height
        .contentShape(Rectangle().size(width: 20, height: viewHeight + 20))
    }
}


struct AudioSegmentEditorView: View {
    @EnvironmentObject var viewModel: SamplerViewModel
    @Environment(\.dismiss) var dismiss

    let audioFileURL: URL
    let targetNoteOverride: Int?

    // --- State for Audio Data & Waveform ---
    @State private var audioFile: AVAudioFile? = nil
    @State private var audioInfo: String = "Loading audio..."
    @State private var totalFrames: Int64? = nil
    @State private var waveformRMSData: [Float] = []
    @State private var isLoadingWaveform = true

    // --- State for Markers & Segments (CHANGED TYPE) ---
    @State private var markers: [Double] = [] // Store Normalized Positions (0.0 to 1.0)
    @State private var selectedSegmentIndex: Int? = nil

    // --- State for Mapping ---
    @State private var targetMidiNote: Int // Initialized in init

    // --- Computed property for the full MIDI range (0-127) ---
    private var availablePianoKeys: [PianoKey] { viewModel.pianoKeys }
    private var availableMidiNoteRange: Range<Int> { 0..<128 }

    // --- State for Dragging Markers ---
    @State private var draggedMarkerIndex: Int? = nil
    @GestureState private var dragOffset: CGSize = .zero

    // --- Auto-Mapping State ---
    @State private var autoMapStartNote: Int = 24 // Default C0
    @State private var velocityMapTargetNote: Int = 60 // Default C4
    @State private var roundRobinTargetNote: Int = 60 // Default C4

    // --- Transient Detection State ---
    // Threshold: Lower value = MORE sensitive (detects smaller changes)
    // Slider: 0.01 (Max Sensitivity) to 0.99 (Min Sensitivity)
    @State private var transientThreshold: Double = 0.1 // Default sensitivity

    // --- NEW: State for Zoom/Scroll (lifted from WaveformDisplayView) ---
    @State private var horizontalZoom: CGFloat = 1.0
    @State private var scrollOffsetPercentage: CGFloat = 0.0
    // ------------------------------------------------------------------

    // --- Computed Property: Number of Segments ---
    private var numberOfSegments: Int { markers.count + 1 }

    // Define a constant for the waveform height
    private let waveformViewHeight: CGFloat = 150

    // --- Initializer ---
    init(audioFileURL: URL, targetNoteOverride: Int? = nil) {
        self.audioFileURL = audioFileURL
        self.targetNoteOverride = targetNoteOverride
        _targetMidiNote = State(initialValue: targetNoteOverride ?? 60)
        print("AudioSegmentEditorView initialized for: \(audioFileURL.lastPathComponent)")
    }

    var body: some View {
        VStack(spacing: 15) {
            Text("Audio Segment Editor")
                .font(.title2)

            Text("Editing: \(audioFileURL.lastPathComponent)")
                .font(.caption)
                .lineLimit(1)

            // --- Waveform Display and Markers ---
            ZStack {
                WaveformDisplayView(
                    waveformRMSData: waveformRMSData,
                    horizontalZoom: $horizontalZoom,
                    scrollOffsetPercentage: $scrollOffsetPercentage
                )
                .frame(height: waveformViewHeight)

                // --- Overlay for Transient Markers ---
                if !isLoadingWaveform && !waveformRMSData.isEmpty {
                    GeometryReader { geometry in
                        let currentViewWidth = geometry.size.width

                        // --- Calls to helper functions ---
                        let totalWaveformW = calculateTotalWaveformWidth(viewWidth: currentViewWidth)
                        let scrollOffsetPts = calculateCurrentScrollOffsetPoints(viewWidth: currentViewWidth)

                        // --- CORRECTED Marker Positioning (using Normalized Values) ---
                        ForEach(markers.indices, id: \.self) { index in
                            let isDraggingThisMarker = (draggedMarkerIndex == index)
                            let markerValue = markers[index] // Get normalized value

                            // Convert normalized value to view X position using REVERTED helper
                            let viewX = xPositionForMarker(markerValue: markerValue, viewWidth: currentViewWidth, totalWaveformW: totalWaveformW, scrollOffsetPts: scrollOffsetPts)

                            // Only display if within view bounds
                            if viewX >= -1 && viewX <= currentViewWidth + 1 {
                                let currentXPosition = isDraggingThisMarker ? viewX + dragOffset.width : viewX
                                let clampedXPosition = max(0, min(currentViewWidth, currentXPosition))

                                // --- UPDATED DEBUG PRINT ---
                                let _ = print("  -> Marker[\(index)]: Value=\(String(format: "%.4f", markerValue)), ViewX=\(String(format: "%.2f", viewX)), ClampedX=\(String(format: "%.2f", clampedXPosition)), Width=\(String(format: "%.0f", currentViewWidth)), TotalW=\(String(format: "%.0f", totalWaveformW)), Offset=\(String(format: "%.0f", scrollOffsetPts))")
                                
                                MarkerView(isBeingDragged: .constant(isDraggingThisMarker), viewHeight: geometry.size.height)
                                    .position(x: clampedXPosition, y: geometry.size.height / 2)
                                    .onTapGesture(count: 2) {
                                        print("Double tapped marker index: \(index)")
                                        deleteMarker(at: index)
                                    }
                                    .gesture(
                                        DragGesture(minimumDistance: 1)
                                            .updating($dragOffset) { value, state, _ in
                                                state = value.translation
                                                DispatchQueue.main.async {
                                                     if self.draggedMarkerIndex == nil { self.draggedMarkerIndex = index }
                                                 }
                                            }
                                            .onEnded { value in
                                                // Pass necessary info to finalize (using REVERTED logic)
                                                finalizeMarkerDrag(index: index, originalViewX: viewX, dragTranslation: value.translation, currentViewWidth: currentViewWidth, totalWaveformWidth: totalWaveformW, scrollOffsetPoints: scrollOffsetPts)
                                                self.draggedMarkerIndex = nil
                                            }
                                    )
                            } else { EmptyView() }
                        } // End ForEach

                        // Attach tap gesture HERE (Using REVERTED logic)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                             if draggedMarkerIndex == nil, !isLoadingWaveform, !waveformRMSData.isEmpty {
                                 // Convert tap location to normalized position using REVERTED helper
                                 let newNormalizedPosition = normalizedPositionForViewX(value.location.x, viewWidth: currentViewWidth, totalWaveformW: totalWaveformW, scrollOffsetPts: scrollOffsetPts)
                                 // Call REVERTED addMarker
                                 addMarker(normalizedPosition: newNormalizedPosition, currentViewWidth: currentViewWidth, totalWaveformWidth: totalWaveformW)
                             }
                         })
                        .clipped()
                    } // End GeometryReader
                    .frame(height: waveformViewHeight)
                } // End if !isLoadingWaveform
            } // End ZStack
            .padding(.horizontal)
            .padding(.bottom, 10)

            // --- Time Zoom Slider (Moved here) ---
            HStack {
                Text("Time:").frame(width: 80, alignment: .leading)
                Slider(value: $horizontalZoom, in: 1.0...50.0) // Min zoom 1x
                Text(String(format: "%.1fx", horizontalZoom)).frame(width: 40)
            }
            .padding(.horizontal)
            .font(.caption)
            // --- END Time Zoom Slider ---

            // --- Marker Controls ---
            HStack {
                 Button("Clear All Markers") { markers.removeAll(); selectedSegmentIndex = nil }
                 .disabled(markers.isEmpty)
                 Spacer()
                 VStack(alignment: .trailing) {
                     Button("Detect Transients") { detectAndSetTransients() }
                     // Disable if loading or file missing
                     .disabled(isLoadingWaveform || audioFile == nil)
                     HStack {
                         Text("Sensitivity:")
                         // Slider: 0.01 (Max Sensitivity) to 0.99 (Min Sensitivity)
                         Slider(value: $transientThreshold, in: 0.01...0.99)
                             .frame(width: 100)
                     }
                     .font(.caption)
                 }
             }
             .padding(.horizontal)

            // --- Segment Information & Mapping ---
            Text(audioInfo)
                 .font(.footnote)
            Text("Segments Defined: \(numberOfSegments)")
                 .font(.footnote)

            Divider().padding(.vertical, 5)
            Text("Mapping Options").font(.headline)

            // --- CONDITIONAL MAPPING CONTROLS ---
            if let targetNote = targetNoteOverride {
                // --- SINGLE NOTE MAPPING (When opened from a specific key) ---
                Text("Map All Segments to Note: \(SamplerViewModel.noteNumberToName(targetNote)) (\(targetNote))")
                    .font(.subheadline)
                Button("Map \(numberOfSegments) Segment\(numberOfSegments == 1 ? "" : "s") to Note \(targetNote)") {
                    mapAllSegmentsToSingleNote(targetNote: targetNote)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingWaveform || audioFile == nil)
            } else {
                // --- MULTI-NOTE MAPPING (When opened from import) ---
                 VStack(alignment: .leading, spacing: 8) {
                     // Auto-Map Consecutive
                     HStack {
                         Button("Map Consecutively") { mapSegmentsConsecutively() }
                         .buttonStyle(.bordered)
                         Text("starting from")
                         Picker("Start Note", selection: $autoMapStartNote) {
                             ForEach(availableMidiNoteRange, id: \.self) { note in
                                 // Call static function
                                 Text("\(SamplerViewModel.noteNumberToName(note)) (\(note))").tag(note)
                             }
                         }
                         .pickerStyle(.menu).frame(width: 150).labelsHidden()
                     }
                     // Velocity Layering
                     HStack {
                         Button("Map Velocity Layers") { mapSegmentsAsVelocityLayers() }
                         .buttonStyle(.bordered)
                         Text("on note")
                         Picker("Target Note", selection: $velocityMapTargetNote) {
                            ForEach(availableMidiNoteRange, id: \.self) { note in
                                // Call static function
                                Text("\(SamplerViewModel.noteNumberToName(note)) (\(note))").tag(note)
                            }
                         }
                         .pickerStyle(.menu).frame(width: 150).labelsHidden()
                     }
                     // Round Robin
                     HStack {
                         Button("Map Round Robin") { mapSegmentsAsRoundRobins() }
                         .buttonStyle(.bordered)
                         Text("on note")
                         Picker("Target Note", selection: $roundRobinTargetNote) {
                            ForEach(availableMidiNoteRange, id: \.self) { note in
                                // Call static function
                                Text("\(SamplerViewModel.noteNumberToName(note)) (\(note))").tag(note)
                            }
                         }
                         .pickerStyle(.menu).frame(width: 150).labelsHidden()
                     }
                 }
                 // Fallback/Quick Map All
                 Button("Map All Segments to C4 (60)") { mapAllSegmentsToSingleNote(targetNote: 60) }
                 .padding(.top, 5)
            } // End else for targetNoteOverride check

            Spacer() // Pushes content to the top

            // --- Dismiss Button ---
            Button("Done") { dismiss() }
            .buttonStyle(.bordered)
            .padding(.bottom)

        } // End Main VStack
        .padding()
        // --- UPDATED ALERT ---
        .alert("Error", isPresented: $viewModel.showingErrorAlert) { // Bind to viewModel state
            Button("OK", role: .cancel) {
                 // Optional: Add action to clear error state if needed
                 // viewModel.errorAlertMessage = nil // Might be better handled by the view dismissing
            }
        } message: {
            Text(viewModel.errorAlertMessage ?? "An unknown error occurred.") // Use viewModel message
        }
        .task {
            print("AudioSegmentEditorView .task started")
            await loadInitialAudioData()
            print("AudioSegmentEditorView .task finished")
        }
    }

    // MARK: - Async Loading Functions

    /// Loads the initial audio file info and triggers waveform loading.
    @MainActor // Ensure state updates happen on the main actor
    private func loadInitialAudioData() async {
        print("Executing loadInitialAudioData()")
        isLoadingWaveform = true // Set loading state
        audioInfo = "Loading audio..."

        do {
            // Start accessing security-scoped resource if needed
            let securityScoped = audioFileURL.startAccessingSecurityScopedResource()
            defer { if securityScoped { audioFileURL.stopAccessingSecurityScopedResource() } }

            let file = try AVAudioFile(forReading: audioFileURL)
            let frames = file.length
            let duration = Double(frames) / file.processingFormat.sampleRate
            let info = String(format: "Duration: %.2f s, Rate: %.1f kHz, Frames: %lld",
                               duration,
                               file.processingFormat.sampleRate / 1000,
                               frames)

            // Update state (safe because we're on MainActor)
            self.audioFile = file
            self.totalFrames = frames
            self.audioInfo = info
            print(" -> Audio info loaded successfully.")

            // Trigger waveform loading (also needs to be async)
            await self.loadWaveform()

        } catch {
            let errorMsg = "Error loading audio info: \(error.localizedDescription)"
            // Update state (safe because we're on MainActor)
            self.audioInfo = errorMsg
            self.isLoadingWaveform = false // Stop loading on error
            // Optionally show error alert via ViewModel
            // viewModel.showError("Failed to load audio file: \(error.localizedDescription)")
            print(" -> \(errorMsg)")
        }
    }

    /// Loads the waveform data for display.
    @MainActor // Ensure state updates happen on the main actor
    func loadWaveform() async {
        guard let file = audioFile else {
            self.audioInfo = "Error: Audio file ref missing for waveform."
            self.isLoadingWaveform = false
            self.waveformRMSData = []
            print("loadWaveform: Audio file missing.")
            return
        }
        
        print("Executing loadWaveform()")
        // Call ViewModel's function - Expects [Float]?
        let rmsDataResult = await viewModel.getWaveformRMSData(for: file.url)

        // Update state (safe because we're on MainActor)
        if let rmsValues = rmsDataResult {
            if !rmsValues.isEmpty {
                self.waveformRMSData = rmsValues // Store data
                print(" -> Successfully loaded \(rmsValues.count) RMS samples")
                // Update audioInfo only if successful (overwrites loading message)
                 let duration = Double(file.length) / file.processingFormat.sampleRate
                 self.audioInfo = String(format: "Duration: %.2f s, Rate: %.1f kHz, Frames: %lld",
                                        duration, file.processingFormat.sampleRate / 1000, file.length)
            } else {
                self.audioInfo = "Waveform generation resulted in empty data."
                self.waveformRMSData = []
                print(" -> Waveform generation resulted in empty data.")
            }
        } else {
            self.audioInfo = "Error generating waveform."
            self.waveformRMSData = []
            print(" -> Waveform generation failed or returned nil.")
            viewModel.showError("Failed to generate waveform data.")
        }
        self.isLoadingWaveform = false
    }

    // MARK: - Coordinate/Frame Conversion Helpers (Moved Out)
    private func calculateTotalWaveformWidth(viewWidth: CGFloat) -> CGFloat {
        viewWidth * horizontalZoom
    }
    private func calculateCurrentScrollOffsetPoints(viewWidth: CGFloat) -> CGFloat {
        let totalWidth = calculateTotalWaveformWidth(viewWidth: viewWidth)
        let excessW = max(0, totalWidth - viewWidth)
        return excessW * scrollOffsetPercentage
    }

    // --- REVERTED: Calculates X position directly from normalized marker value ---
    private func xPositionForMarker(markerValue: Double, viewWidth: CGFloat, totalWaveformW: CGFloat, scrollOffsetPts: CGFloat) -> CGFloat {
        let absoluteX = markerValue * totalWaveformW
        return absoluteX - scrollOffsetPts
    }

    // --- REVERTED: Calculates normalized position from view X coordinate ---
    private func normalizedPositionForViewX(_ xPositionInView: CGFloat, viewWidth: CGFloat, totalWaveformW: CGFloat, scrollOffsetPts: CGFloat) -> Double {
        guard totalWaveformW > 0 else { return 0.0 } // Avoid division by zero
        let absoluteX = xPositionInView + scrollOffsetPts
        let normalizedPosition = absoluteX / totalWaveformW
        return max(0.0, min(1.0, normalizedPosition)) // Clamp [0.0, 1.0]
    }

    // MARK: - Marker Logic (Transient Markers) - UPDATED for Normalized Positions

    // --- REVERTED: Works with normalized positions ---
    func addMarker(normalizedPosition: Double, currentViewWidth: CGFloat, totalWaveformWidth: CGFloat) {
        // Clamp input position just in case
        let newMarkerValue = max(0.0, min(1.0, normalizedPosition))

        // --- Min distance check (using normalized values) ---
        let minPixelDistance: CGFloat = 5.0
        let minNormalizedDistance: Double = totalWaveformWidth > 0 ? (minPixelDistance / totalWaveformWidth) : 0.001 // Avoid div by zero

        if markers.contains(where: { abs($0 - newMarkerValue) < minNormalizedDistance }) {
            print("Marker too close to an existing one (norm distance: \(minNormalizedDistance)).")
            return
        }
        // -----------------------------------------------
        
        markers.append(newMarkerValue)
        markers.sort()
        print("Added marker at normalized position: \(newMarkerValue)")
        selectedSegmentIndex = nil
    }

    // --- REVERTED: Works with normalized positions ---
    func finalizeMarkerDrag(index: Int, originalViewX: CGFloat, dragTranslation: CGSize, currentViewWidth: CGFloat, totalWaveformWidth: CGFloat, scrollOffsetPoints: CGFloat) {
        guard index >= 0 && index < markers.count else { return }
        guard totalWaveformWidth > 0 else { return } // Need width for calc
        
        // Calculate new view X based on drag
        let newViewX = originalViewX + dragTranslation.width
        
        // Convert new view X back to new normalized position using helper
        let newNormalizedValue = normalizedPositionForViewX(newViewX, viewWidth: currentViewWidth, totalWaveformW: totalWaveformWidth, scrollOffsetPts: scrollOffsetPoints)
        
        markers[index] = newNormalizedValue
        markers.sort()
        print("Moved marker \(index) to normalized position: \(newNormalizedValue)")
    }

    // --- REVERTED: Works with normalized positions ---
    func deleteMarker(at index: Int) {
        guard index >= 0 && index < markers.count else { return }
        let removedValue = markers.remove(at: index)
        print("Removed marker at index \(index) (normalized value: \(removedValue)") // Updated log
        if selectedSegmentIndex == index { selectedSegmentIndex = nil }
        else if selectedSegmentIndex ?? -1 > index { selectedSegmentIndex! -= 1 }
    }

    // MARK: - Transient Detection (UPDATED Call)
    func detectAndSetTransients() {
        guard !waveformRMSData.isEmpty else {
            viewModel.showError("Cannot detect transients: Waveform data not loaded.")
            return
        }
        guard let totalAudioFrames = self.totalFrames, totalAudioFrames > 0 else {
            viewModel.showError("Cannot detect transients: Total audio frame count is missing.")
            return
        }
        // samplesPerPixel is no longer needed for the detectTransients call itself

        Task {
            do {
                print("Starting transient detection with threshold: \(transientThreshold)...")
                // --- Ensure samplesPerPixel argument is REMOVED here ---
                let detectedNormalizedPositions = try viewModel.detectTransients(
                    rmsData: waveformRMSData,
                    threshold: Float(transientThreshold),
                    totalFrames: totalAudioFrames // Pass for context/validation within ViewModel
                )
                // ----------------------------------------------------------

                DispatchQueue.main.async {
                    self.markers = detectedNormalizedPositions.sorted() // Assign [Double] directly
                    print("Detected and set \(self.markers.count) transient markers (normalized positions).")
                    self.selectedSegmentIndex = nil
                }
            } catch {
                DispatchQueue.main.async {
                    // --- Improved Error Logging ---
                    let nsError = error as NSError
                    let errorMessage = "Transient detection failed: \(error.localizedDescription) (Domain: \(nsError.domain), Code: \(nsError.code), UserInfo: \(nsError.userInfo))"
                    print("Transient detection error detailed: \(errorMessage)")
                    // -----------------------------

                    // FIXED: Use showError for consistency
                    // Display a slightly simpler message to the user
                    viewModel.showError("Transient detection failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Mapping Logic (UPDATED)

    // --- REVERTED & CORRECTED: Calculates segment boundaries as frame indices from Double markers ---
    func getSegmentBoundaries() -> [(start: Int64, end: Int64)] {
        guard let totalAudioFrames = totalFrames, totalAudioFrames > 0 else {
            print("Warning: Cannot get segment boundaries without totalFrames.")
            return []
        }
        
        var segments: [(start: Int64, end: Int64)] = []
        var lastMarkerValue: Double = 0.0
        
        for markerValue in markers.sorted() {
            // Ensure markerValue is valid and greater than the last
            guard markerValue > lastMarkerValue && markerValue <= 1.0 && lastMarkerValue >= 0.0 else {
                print("Warning: Skipping invalid or zero-length segment boundary near normalized value \(markerValue)")
                lastMarkerValue = max(lastMarkerValue, markerValue) // Avoid getting stuck
                continue
            }
            
            // Convert normalized boundaries to frame indices
            let startFrame = Int64(lastMarkerValue * Double(totalAudioFrames))
            let endFrame = Int64(markerValue * Double(totalAudioFrames))
            
            // Ensure frame indices result in a valid segment (start < end)
            if endFrame > startFrame {
                 segments.append((start: startFrame, end: endFrame))
            } else {
                 print("Warning: Segment boundaries resulted in zero/negative length frames: [\(startFrame)-\(endFrame)] from norm [\(lastMarkerValue)-\(markerValue)]. Skipping.")
            }
            lastMarkerValue = markerValue
        }
        
        // Add the last segment (from the last marker to the end of the file)
        if lastMarkerValue < 1.0 && lastMarkerValue >= 0.0 {
            let startFrame = Int64(lastMarkerValue * Double(totalAudioFrames))
            let endFrame = totalAudioFrames // End is exclusive for frames
            if endFrame > startFrame {
                segments.append((start: startFrame, end: endFrame))
            }
        }
        
        // Handle the edge case of NO markers (one segment for the whole file)
        if markers.isEmpty {
            segments.append((start: 0, end: totalAudioFrames))
        }
        
        print("Calculated \(segments.count) segment boundaries (frames): \(segments.map { "[\($0.start)-\($0.end)]" }.joined(separator: ", "))")
        return segments
    }

    // Updated to accept frame indices
    func createMultiSampleParts(from segmentBoundaries: [(start: Int64, end: Int64)],
                                mapFunction: (Int, (start: Int64, end: Int64)) -> (note: Int, velocity: VelocityRangeData, rrIndex: Int?)?
                               ) -> [MultiSamplePartData] {
        guard let fileUrl = audioFile?.url, let totalFrames = self.totalFrames, totalFrames > 0 else {
            viewModel.showError("Audio file information not available for mapping.")
            return []
        }
        var partsToAdd: [MultiSamplePartData] = []
        for (index, segment) in segmentBoundaries.enumerated() {
             guard let mapResult = mapFunction(index, segment) else { continue }
             let startSample = segment.start // Use directly
             let endSample = segment.end     // Use directly
             guard startSample < endSample else { continue }
             // Clamping might not be strictly needed if boundaries are correct, but keep for safety
             let finalStartSample = max(0, startSample)
             let finalEndSample = min(totalFrames, endSample)
             guard finalStartSample < finalEndSample else { continue }

            let part = MultiSamplePartData(
                name: fileUrl.deletingPathExtension().lastPathComponent + "_Part\(index+1)",
                keyRangeMin: mapResult.note,
                keyRangeMax: mapResult.note,
                velocityRange: mapResult.velocity,
                sourceFileURL: fileUrl,
                segmentStartSample: finalStartSample,
                segmentEndSample: finalEndSample,
                roundRobinIndex: mapResult.rrIndex,
                relativePath: nil,
                absolutePath: fileUrl.path,
                originalAbsolutePath: fileUrl.path,
                originalFileFrameCount: totalFrames
            )
            partsToAdd.append(part)
            print(" -> Prepared Part \(index + 1): Note=\(mapResult.note), Vel=[\(mapResult.velocity.min)-\(mapResult.velocity.max)], RR=\(mapResult.rrIndex ?? -1), Frames=\(finalStartSample)-\(finalEndSample)")
        }
        return partsToAdd
    }
    
    // Mapping functions (mapAllSegments..., mapSegments...) now call the updated createMultiSampleParts
    // They should work correctly as long as createMultiSampleParts uses frame indices properly
    func mapAllSegmentsToSingleNote(targetNote: Int) {
        let segmentBoundaries = getSegmentBoundaries() // Returns [(Int64, Int64)]
        guard !segmentBoundaries.isEmpty else { /* ... */ return }
        print("Mapping \(segmentBoundaries.count) segments to note \(targetNote)...")
        let parts = createMultiSampleParts(from: segmentBoundaries) { index, segment in
            return (note: targetNote, velocity: .fullRange, rrIndex: nil)
        }
        if !parts.isEmpty {
            viewModel.addMultiSampleParts(parts)
            print("Added \(parts.count) parts to ViewModel for note \(targetNote).")
            dismiss()
        } else { /* ... */ }
    }
     func mapSegmentsConsecutively() {
         let segmentBoundaries = getSegmentBoundaries()
         guard !segmentBoundaries.isEmpty else { /* ... */ return }
         print("Mapping \(segmentBoundaries.count) segments consecutively starting from note \(autoMapStartNote)...")
         let parts = createMultiSampleParts(from: segmentBoundaries) { index, segment in
             let targetNote = autoMapStartNote + index
             guard targetNote <= 127 else { return nil }
             return (note: targetNote, velocity: .fullRange, rrIndex: nil)
         }
         if !parts.isEmpty {
             viewModel.addMultiSampleParts(parts)
             print("Added \(parts.count) consecutively mapped parts to ViewModel.")
             dismiss()
         } else { /* ... */ }
     }
     func mapSegmentsAsVelocityLayers() {
          let segmentBoundaries = getSegmentBoundaries()
          let numberOfSegments = segmentBoundaries.count
          guard numberOfSegments > 0 else { /* ... */ return }
          print("Mapping \(numberOfSegments) segments as velocity layers on note \(velocityMapTargetNote)...")
          let velocityRanges = viewModel.calculateSeparateVelocityRanges(numberOfFiles: numberOfSegments)
          guard velocityRanges.count == numberOfSegments else { /* ... */ return }
          let parts = createMultiSampleParts(from: segmentBoundaries) { index, segment in
              return (note: velocityMapTargetNote, velocity: velocityRanges[index], rrIndex: nil)
          }
          if !parts.isEmpty {
              viewModel.addMultiSampleParts(parts)
              print("Added \(parts.count) velocity layer parts to ViewModel for note \(velocityMapTargetNote).")
              dismiss()
          } else { /* ... */ }
      }
      func mapSegmentsAsRoundRobins() {
          let segmentBoundaries = getSegmentBoundaries()
          let numberOfSegments = segmentBoundaries.count
          guard numberOfSegments > 0 else { /* ... */ return }
          print("Mapping \(numberOfSegments) segments as round robins on note \(roundRobinTargetNote)...")
          let parts = createMultiSampleParts(from: segmentBoundaries) { index, segment in
              return (note: roundRobinTargetNote, velocity: .fullRange, rrIndex: index)
          }
          if !parts.isEmpty {
              viewModel.addMultiSampleParts(parts)
              viewModel.setMappingMode(.roundRobin)
              print("Added \(parts.count) round robin parts to ViewModel for note \(roundRobinTargetNote).")
              dismiss()
          } else { /* ... */ }
      }
} // End struct


// --- Previews --- (Keep as is)
struct AudioSegmentEditorView_Previews: PreviewProvider {
    static var previews: some View {
        let dummyURL = URL(fileURLWithPath: "/path/to/dummy/audio.wav")
        let viewModel = SamplerViewModel()
        AudioSegmentEditorView(audioFileURL: dummyURL)
            .environmentObject(viewModel)
            .previewDisplayName("Editor - No Override")
        AudioSegmentEditorView(audioFileURL: dummyURL, targetNoteOverride: 60)
            .environmentObject(viewModel)
            .previewDisplayName("Editor - Target C4")
    }
}
