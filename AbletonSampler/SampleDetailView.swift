import SwiftUI
import AVFoundation // For audio file info
import AudioKit // For potential audio processing/waveform data
import UniformTypeIdentifiers // Needed for UTType.fileURL
// Remove AudioKitUI import if WaveformView is not used directly anymore
// import AudioKitUI

// -----------------------------------------


// --- REMOVE OLD Placeholder Waveform View ---
// struct SampleDetailWaveformView: View { ... }
// -----------------------------------------

// --- Helper View for Round Robin Cells ---
private struct RoundRobinCellView: View {
    let index: Int
    let sample: MultiSamplePartData
    let robinWidth: CGFloat
    let zoneHeight: CGFloat
    let onSelect: (MultiSamplePartData) -> Void // Add selection closure

    var body: some View {
        Rectangle()
            .fill(Color.orange.opacity(0.6)) // Color for Round Robins
            .frame(width: robinWidth, height: zoneHeight)
            .border(Color.black.opacity(0.5), width: 0.5)
            .overlay(
                VStack {
                    Text("RR \(index + 1)") // Simple RR Index label
                    Text(sample.sourceFileURL.lastPathComponent)
                       .font(.caption2)
                       .lineLimit(2) // Allow slightly more text wrap
                       .truncationMode(.tail)
                }
                .font(.caption)
                .foregroundColor(.white)
                .padding(2)
                .minimumScaleFactor(0.5),
                alignment: .center
            )
            .contentShape(Rectangle()) // Make the whole area tappable
            .onTapGesture {
                onSelect(sample) // Call closure on tap
            }
    }
}

// --- Helper View for Velocity Zone Cells ---
private struct VelocityZoneCellView: View {
    let sample: MultiSamplePartData
    let totalWidth: CGFloat
    let totalHeight: CGFloat
    let onSelect: (MultiSamplePartData) -> Void // Add selection closure

    var body: some View {
        // Perform calculations inside the cell view
        let minVelocity = CGFloat(sample.velocityRange.min)
        let maxVelocity = CGFloat(sample.velocityRange.max)
        let velocitySpan = maxVelocity - minVelocity + 1
        // Ensure minimum height of 1, avoid division by zero if totalHeight is 0
        let zoneHeight = max(1, (velocitySpan / 128.0) * max(1, totalHeight))

        // Calculate Y position
        let zoneTopY = (1.0 - (maxVelocity + 1.0) / 128.0) * max(1, totalHeight)
        let zoneCenterY = zoneTopY + zoneHeight / 2.0

        // Add guard check here, return EmptyView if invalid
        guard zoneCenterY.isFinite else {
            // Optional: Log error here if needed, outside ViewBuilder context is tricky
            // print("VelocityZoneCellView: Skipping draw - Invalid center Y for sample \(sample.sourceFileURL.lastPathComponent)")
            return AnyView(EmptyView()) // Return empty view if calculation fails
        }

        // Return the actual view content if calculations are valid
        return AnyView(
            Rectangle()
                .fill(Color.blue.opacity(0.6)) // Color for Velocity Zones
                .frame(width: totalWidth, height: zoneHeight)
                .border(Color.black.opacity(0.5), width: 0.5)
                .overlay(
                    Text("Vel: \(sample.velocityRange.min)-\(sample.velocityRange.max)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(2)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1),
                    alignment: .center
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(sample) // Call closure on tap
                }
        )
    }
}

// Define this struct OUTSIDE or INSIDE SampleDetailView, but not inside a function body

struct EditableVelocityView: View {
    // --- REMOVE @EnvironmentObject ---
    // @EnvironmentObject var viewModel: SamplerViewModel

    // --- ADD viewModel as a regular property ---
    let viewModel: SamplerViewModel // Pass explicitly

    let sample: MultiSamplePartData // The sample being edited
    let midiNote: Int              // Need the note for the update function

    // --- Local state for editing velocity ---
    @State private var minVelocityString: String
    @State private var maxVelocityString: String
    @State private var validationError: String? = nil // To show validation errors

    // --- Update init to accept viewModel ---
    init(viewModel: SamplerViewModel, sample: MultiSamplePartData, midiNote: Int) {
        self.viewModel = viewModel // Assign passed viewModel
        self.sample = sample
        self.midiNote = midiNote
        // Initialize @State properties in the initializer
        _minVelocityString = State(initialValue: "\(sample.velocityRange.min)")
        _maxVelocityString = State(initialValue: "\(sample.velocityRange.max)")
        // validationError starts as nil implicitly
        print("EditableVelocityView init for \(sample.id). Initial min/max strings: \(minVelocityString)/\(maxVelocityString)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // --- Display Current Velocity (Read-only part) ---
            HStack {
                Text("Current Velocity:")
                    .font(.caption).foregroundColor(.secondary)
                Text("\(sample.velocityRange.min) - \(sample.velocityRange.max)")
                Spacer()
            }

            // --- Editable Fields ---
            HStack {
                Text("Edit Min:")
                TextField("0", text: $minVelocityString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    #if os(macOS)
                    .frame(maxWidth: 50)
                    #else
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 50) // iOS/iPadOS
                    #endif

                Text("Max:")
                TextField("127", text: $maxVelocityString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    #if os(macOS)
                    .frame(maxWidth: 50)
                    #else
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 50) // iOS/iPadOS
                    #endif

                Spacer() // Push fields left

                // --- Use explicit Button(action:label:) syntax ---
                Button {
                    // Action:
                    validateAndUpdate()
                } label: {
                    // Label:
                    Text("Update Velocity")
                }
                // Disable button if the text fields haven't changed from the original sample values
                .disabled(minVelocityString == "\(sample.velocityRange.min)" && maxVelocityString == "\(sample.velocityRange.max)")
            }

            // Display validation errors if any
            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 5)
        // --- Update local state if the *input* sample data changes ---
        // This handles cases where the update succeeds and the parent view passes new sample data
        .onChange(of: sample.velocityRange) { oldRange, newRange in
             print("EditableVelocityView saw underlying sample \(sample.id) velocityRange change externally from \(oldRange) to \(newRange). Updating text fields.") // Debugging
             minVelocityString = "\(newRange.min)"
             maxVelocityString = "\(newRange.max)"
             validationError = nil // Clear error on external update
        }
        // No .id needed here as the struct itself will be recreated if the sample ID changes
        // in the parent view. onAppear can ensure initial state correctness if needed,
        // but init handles it here.
         // .onAppear { // Optional: Verify initial state if needed
         //    print("EditableVelocityView appearing for \(sample.id). Current min/max strings: \(minVelocityString)/\(maxVelocityString)")
         // }
    }

    // Helper function for validation and calling the ViewModel update
    private func validateAndUpdate() {
        validationError = nil // Clear previous error
        guard let minVel = Int(minVelocityString),
              let maxVel = Int(maxVelocityString) else {
            validationError = "Invalid number format."
            print("Validation Error: Invalid number format. Min='\(minVelocityString)', Max='\(maxVelocityString)'")
            return // Use return here, it's fine in a normal function
        }

        guard minVel >= 0 && minVel <= 127 && maxVel >= 0 && maxVel <= 127 else {
            validationError = "Velocity must be 0-127."
            print("Validation Error: Velocity out of range. Min=\(minVel), Max=\(maxVel)")
            return // Use return
        }

        guard minVel <= maxVel else {
            validationError = "Min velocity cannot exceed Max."
            print("Validation Error: Min (\(minVel)) > Max (\(maxVel))")
            return // Use return
        }

        // --- If validation passes, update the ViewModel ---
        // Create the specific VelocityRangeData type your ViewModel expects
        let newRange = VelocityRangeData(min: minVel, max: maxVel, crossfadeMin: minVel, crossfadeMax: maxVel) // Adjust crossfade logic if needed
        print("EditableVelocityView: Attempting to update Sample ID \(sample.id) (Note: \(midiNote)) to Velocity Range: Min=\(newRange.min), Max=\(newRange.max)") // Debugging
        // --- Call the ViewModel using the explicitly passed property ---
        viewModel.updateVelocityRange(note: midiNote, sampleID: sample.id, newRange: newRange)
    }
}

struct SampleDetailView: View {
    @EnvironmentObject var viewModel: SamplerViewModel

    let midiNote: Int
    let requestSegmentation: (URL, Int) -> Void // Closure to request editor presentation

    // --- State for selection and details ---
    @State private var selectedSampleForDetails: MultiSamplePartData? = nil {
        didSet {
            // Avoid infinite loops if setting programmatically triggers didSet
            // Though comparing optionals directly should work
            if oldValue != selectedSampleForDetails {
                 print("** didSet(selectedSampleForDetails) ** Selection changed. Triggering reload.")
                 loadAudioFileDetails() // Load data for the new selection
            }
        }
    }
    @State private var detailDropTargeted: Bool = false

    // --- NEW: State for Waveform Display (Adapted from AudioSegmentEditorView) ---
    @State private var audioFile: AVAudioFile? = nil // Keep track of the loaded file for context
    @State private var totalSourceFileFrames: Int64? = nil // Total frames of the *source* file
    @State private var waveformRMSData: [Float] = [] // Store calculated RMS values
    @State private var maxRMSValue: Float = 0.001 // Avoid division by zero
    @State private var isLoadingWaveform = true
    @State private var amplitudeScale: CGFloat = 1.0 // Vertical scaling
    @State private var timeZoomScale: CGFloat = 1.0 // Horizontal zoom (1.0 = no zoom)
    @State private var scrollOffset: CGPoint = .zero // Current scroll position
    @State private var waveformViewID = UUID() // To force geometry reader update sometimes

    // --- NEW: State for Caching Waveform Data ---
    @State private var cachedWaveformURL: URL? = nil
    @State private var cachedWaveformRMSData: [Float] = []
    @State private var cachedTotalSourceFrames: Int64? = nil
    @State private var cachedMaxRMSValue: Float = 0.001

    var body: some View {
        // --- Use a computed property for clarity ---
        detailViewContent
            .onAppear {
                // Select the first sample initially if multiple exist for waveform loading purposes
                // --- UPDATED: Find first sample from layers --- 
                let firstSample = viewModel.velocityLayers(for: midiNote)
                    .lazy // Avoid creating intermediate arrays if possible
                    .compactMap { $0.samples.first(where: { $0 != nil }) } // Find the first non-nil sample in any layer
                    .first // Take the very first one found
                    
                if let sampleToSelect = firstSample, selectedSampleForDetails == nil {
                     selectedSampleForDetails = sampleToSelect
                     // print("onAppear: Auto-selecting first sample: ID=\(sampleToSelect.id)")
                }
                 loadAudioFileDetails() // Load waveform for the first/selected sample
             }
             // --- REMOVE Temporarily: onChange for zoom/amplitude --- 
             /*
             .onChange(of: timeZoomScale) { // Kept for potential future waveform controls
                  waveformViewID = UUID()
             }
             .onChange(of: amplitudeScale) { // Kept for potential future waveform controls
                  waveformViewID = UUID()
             }
             */
    }

    @ViewBuilder
    private var detailViewContent: some View {
         // Get the layer structure once for this view rendering
         let currentLayers = viewModel.velocityLayers(for: midiNote)
         // Determine if any sample exists across all layers and slots
         // let noteHasSamples = !currentLayers.allSatisfy { $0.isEmpty } // We'll show the grid regardless

         VStack(alignment: .leading, spacing: 15) {
             // --- Header Section ---
             HStack {
                 Text("Sample Details for Note \(midiNote) (\(viewModel.pianoKeys.first { $0.id == midiNote }?.name ?? "N/A"))")
                     .font(.title3)
                 Spacer()
             }
             .padding(.bottom, 5)

             // --- NEW: Configuration Controls ---
             HStack {
                Stepper("Velocity Layers: \(viewModel.noteLayerConfiguration[midiNote] ?? 1)",
                        value: Binding(
                            get: { viewModel.noteLayerConfiguration[midiNote] ?? 1 },
                            set: { newValue in
                                viewModel.noteLayerConfiguration[midiNote] = max(1, newValue)
                                print("Set Layers for note \(midiNote) to \(max(1, newValue))")
                                // Potentially trigger UI update if needed, though binding should handle it
                            }
                        ),
                        in: 1...16) // Allow 1 to 16 layers

                Spacer()

                Stepper("Max Round Robins: \(viewModel.noteRoundRobinConfiguration[midiNote] ?? 1)",
                        value: Binding(
                            get: { viewModel.noteRoundRobinConfiguration[midiNote] ?? 1 },
                            set: { newValue in
                                viewModel.noteRoundRobinConfiguration[midiNote] = max(1, newValue)
                                print("Set Max RRs for note \(midiNote) to \(max(1, newValue))")
                            }
                        ),
                        in: 1...32) // Allow 1 to 32 RRs (adjust range as needed)
             }
             .padding(.bottom, 10)
             // --- End Configuration Controls ---

             // --- Main Content Area ---
             // --- Always Display the Grid ---
             sampleGridView

             // --- Display the Details for the selected sample (if any) ---
             // Conditionally show details OR a placeholder message
             if selectedSampleForDetails != nil {
                 selectedSampleDetailsView
             } else {
                 // Show placeholder if no sample is selected *or* if the note has no samples at all
                 Text(currentLayers.allSatisfy { $0.isEmpty } ? "No sample assigned to this key. Drop audio below or onto the grid." : "Tap a zone/RR in the grid above to see details.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
             }

             // --- Keep the Drop Zone ---
             dropZoneForDetailView // Show drop zone below details/grid
             Spacer() // Push content up
         }
         .padding()
    }

    // --- Extracted Grid View ---
    @ViewBuilder
    private var sampleGridView: some View {
        // --- NEW Grid Logic based on VelocityLayer --- 
        let velocityLayers = viewModel.velocityLayers(for: midiNote)
        let maxRoundRobins = viewModel.noteRoundRobinConfiguration[midiNote] ?? 1
        
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
            let totalWidth = geometry.size.width
            
            // Check for valid configuration and size
            if !velocityLayers.isEmpty && maxRoundRobins > 0 && totalHeight > 0 && totalWidth > 0 {
                // --- Valid Configuration: Draw the Grid --- 
                let robinWidth = totalWidth / CGFloat(maxRoundRobins)
                
                ZStack(alignment: .topLeading) {
                    // Background for the grid area
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .cornerRadius(5)
                        
                    // Draw Layers and Slots
                    // Iterate over indices as a workaround for potential ForEach/Identifiable issues
                    ForEach(velocityLayers.indices, id: \.self) { layerIndex in 
                        // Access the layer using the index
                        let layer = velocityLayers[layerIndex]
                        
                        // --- Restore loop body --- 
                        // Calculate layer geometry
                        let minVelocity = CGFloat(layer.velocityRange.min)
                        let maxVelocity = CGFloat(layer.velocityRange.max)
                        let velocitySpan = max(1, maxVelocity - minVelocity + 1) // Ensure span is at least 1
                        let zoneHeight = max(1.0, (velocitySpan / 128.0) * totalHeight)
                        let zoneTopY = (1.0 - (maxVelocity + 1.0) / 128.0) * totalHeight
                        // Restore center Y calculation for position
                        let zoneCenterY = zoneTopY + zoneHeight / 2.0

                        // Check if geometry is valid using if statement
                        if zoneCenterY.isFinite && zoneHeight.isFinite && zoneHeight > 0 { // Check center Y
                            // Geometry is valid, proceed (inner loop still commented)
                            
                            /* // Keep inner loop commented */ // Remove start comment marker
                            // Draw slots within this layer
                            ForEach(0..<maxRoundRobins, id: \.self) { rrIndex in
                                // Restore position calculations inside the loop
                                let xPosition = (CGFloat(rrIndex) * robinWidth) + (robinWidth / 2.0)

                                // Check if a sample exists at this specific slot index within the layer's data
                                let sampleDataOptional: MultiSamplePartData? = (rrIndex < layer.samples.count) ? layer.samples[rrIndex] : nil
                                
                                // Decide the cell's appearance
                                if let sampleData = sampleDataOptional {
                                    // --- Occupied Slot ---
                                    Rectangle()
                                        .fill(Color.blue.opacity(0.7))
                                        .frame(width: robinWidth, height: zoneHeight)
                                        .border(Color.black.opacity(0.5), width: 0.5)
                                        .overlay(
                                            VStack {
                                                Text("RR \(rrIndex + 1)")
                                                Text("Vel: \(layer.velocityRange.min)-\(layer.velocityRange.max)")
                                                Text(sampleData.sourceFileURL.lastPathComponent)
                                                   .font(.caption2)
                                                   .lineLimit(1)
                                                   .truncationMode(.middle)
                                            }
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .padding(2)
                                            .minimumScaleFactor(0.5),
                                            alignment: .center
                                        )
                                        // --- APPLY .contentShape BEFORE .position --- 
                                        .contentShape(Rectangle())
                                        .position(x: xPosition, y: zoneCenterY)
                                        // -----------------------------------------
                                        .zIndex(Double(velocityLayers.count - 1 - layerIndex)) // Apply zIndex directly
                                        .onTapGesture {
                                             print("Tapped Occupied Slot: LayerID=\(layer.id), RR=\(rrIndex), SampleID=\(sampleData.id)")
                                             selectedSampleForDetails = sampleData // Update selection
                                        }
                                        .contextMenu { // Add context menu for removal
                                             Button(role: .destructive) {
                                                 viewModel.removeSampleFromGridSlot(layerId: layer.id, rrIndex: rrIndex, forNote: midiNote)
                                             } label: {
                                                 Label("Remove Sample", systemImage: "trash")
                                             }
                                         }
                                } else {
                                    // --- Empty Slot ---
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: robinWidth, height: zoneHeight)
                                        .border(Color.gray.opacity(0.3), width: 0.5)
                                        // --- APPLY .contentShape BEFORE .position --- 
                                        .contentShape(Rectangle())
                                        .position(x: xPosition, y: zoneCenterY)
                                        // -----------------------------------------
                                        .zIndex(Double(velocityLayers.count - 1 - layerIndex)) // Apply zIndex directly
                                        .onTapGesture {
                                             print("Tapped Empty Slot: LayerID=\(layer.id), RR=\(rrIndex)")
                                             // Optionally clear selection or prepare for drop?
                                             selectedSampleForDetails = nil // Clear selection when tapping empty slot
                                        }
                                }
                            } // End ForEach rrIndex
                            /* */ // Remove end comment marker
                            
                        } else {
                            // Geometry is invalid, print warning and do nothing further for this layer
                            let _ = print("Warning: Skipping layer draw due to invalid geometry for range \\(layer.velocityRange.min)-\\(layer.velocityRange.max)")
                            // Implicitly continue to next layer index by finishing this iteration
                        }
                        // --- End loop body --- 
                    } // End ForEach layerIndex
                } // End ZStack
                // --- Add Drop Target (Modified) ---
                .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers, location in // Accept fileURL
                     print("Drop detected at location: \\(location)")
                     guard let provider = providers.first else { return false }
     
                     let numLayers = viewModel.noteLayerConfiguration[midiNote] ?? 1
                     let currentMaxRR = viewModel.noteRoundRobinConfiguration[midiNote] ?? 1 // Use current config
                     guard numLayers > 0, currentMaxRR > 0, totalHeight > 0, totalWidth > 0 else { return false }
     
                     // Calculate target Layer index (using equal height assumption is okay here for index finding)
                     let approxLayerHeight = totalHeight / CGFloat(numLayers)
                     let targetLayerIndex = min(numLayers - 1, max(0, Int(location.y / approxLayerHeight)))
                     
                     // Calculate target RR index
                     let finalRobinWidth = totalWidth / CGFloat(currentMaxRR) // Use correct width for calculation
                     let targetRRIndex = min(currentMaxRR - 1, max(0, Int(location.x / finalRobinWidth)))
     
                     print("  -> Calculated Target Slot: Layer \\(targetLayerIndex), RR \\(targetRRIndex)")
     
                     _ = provider.loadObject(ofClass: URL.self) { url, error in
                          // --- ADD more specific error handling and WAV check ---
                          if let error = error {
                              print("Error loading dropped item provider: \\(error.localizedDescription)")
                              Task { @MainActor in viewModel.showError("Error reading dropped file: \\(error.localizedDescription)") }
                              return
                          }
                          guard let fileURL = url else {
                              print("Error: Dropped item URL is nil")
                              Task { @MainActor in viewModel.showError("Could not read the dropped file.") }
                              return
                          }
                          guard fileURL.pathExtension.lowercased() == "wav" else {
                              print("Error: Dropped file is not a WAV: \\(fileURL.path)")
                              Task { @MainActor in viewModel.showError("Only WAV files can be dropped onto the grid.") }
                              return
                          }
                          print("  -> Dropped File URL: \\(fileURL.path)")
                          DispatchQueue.main.async {
                              guard let metadata = viewModel.extractAudioMetadata(fileURL: fileURL) else { print("Error: Could not extract metadata..."); return }
                              let tempPartData = MultiSamplePartData(name: fileURL.deletingPathExtension().lastPathComponent, keyRangeMin: midiNote, keyRangeMax: midiNote, velocityRange: .fullRange, sourceFileURL: fileURL, segmentStartSample: 0, segmentEndSample: metadata.frameCount ?? 0, relativePath: nil, absolutePath: fileURL.path, originalAbsolutePath: fileURL.path, sampleRate: metadata.sampleRate, fileSize: metadata.fileSize, crc: nil, lastModDate: metadata.lastModDate, originalFileFrameCount: metadata.frameCount)
                              viewModel.addSampleToGridSlot(partData: tempPartData, layerIndex: targetLayerIndex, rrIndex: targetRRIndex, forNote: midiNote)
                          }
                     }
                     // --- End specific error handling ---
                     return true
                 }
                 // --- End Drop Target --- 
                 
            } else {
                // --- Invalid Configuration: Show Message --- 
                Text("Grid cannot be displayed. Check configuration or layout.")
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color.secondary.opacity(0.1))
            }
        } // End GeometryReader
        .frame(height: 150) // Restore desired frame height for the grid
        .padding(.bottom)
    }

    // --- View for Selected Sample Details ---
    @ViewBuilder
    private var selectedSampleDetailsView: some View {
        // Use the currently selected sample for display
        if let sample = selectedSampleForDetails {
            let _ = print("** selectedSampleDetailsView ** Rendering details for sample: ID=\(sample.id), Segment=\(sample.segmentStartSample)-\(sample.segmentEndSample)")
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("Selected Sample Details:")
                    .font(.headline)
                Text("File: \(sample.sourceFileURL.lastPathComponent)")
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // --- Display Segment Info ---
                HStack {
                   VStack(alignment: .leading) {
                       Text("Segment Start:")
                           .font(.caption).foregroundColor(.secondary)
                       Text("\(sample.segmentStartSample) samples")
                   }
                   Spacer()
                   VStack(alignment: .trailing) {
                       Text("Segment End:")
                           .font(.caption).foregroundColor(.secondary)
                       Text("\(sample.segmentEndSample) samples")
                   }
                }
                // Display total source file frames (using state, could be from cache)
                if let totalFrames = totalSourceFileFrames {
                     Text("Source File Total Frames: \(totalFrames)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // --- USE THE NEW STRUCT for Editable Velocity Section ---
                Divider() // Add separator
                // --- Pass viewModel explicitly ---
                EditableVelocityView(viewModel: self.viewModel, sample: sample, midiNote: midiNote)
                // --- End USE THE NEW STRUCT ---


                // --- Waveform Display Area ---
                Text("Waveform:")
                    .font(.headline)
                    .padding(.top, 5)
                 waveformDisplayArea(sampleToDisplay: sample)

            }
            .padding(.top)
        } else {
            // Optionally show a placeholder if no sample is selected
            Text("Tap a zone/RR in the grid above to see details.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }


    // --- Drop Zone View Builder (Unchanged) ---
    @ViewBuilder
    private var dropZoneForDetailView: some View {
        VStack {
            HStack {
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.title3)
                Text("Drop WAV to add to Note \(midiNote)")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(detailDropTargeted ? Color.blue.opacity(0.5) : Color.secondary.opacity(0.2))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(detailDropTargeted ? Color.white : Color.clear, lineWidth: 2)
        )
        .padding(.top, 5)
        .onDrop(of: [UTType.fileURL], isTargeted: $detailDropTargeted) { providers -> Bool in
             guard providers.count == 1 else {
                 viewModel.showError("Please drop only a single WAV file here.")
                 return false
             }
             return handleDetailDrop(providers: providers)
        }
        .animation(.easeInOut(duration: 0.1), value: detailDropTargeted)
    }

    // --- UPDATED Drop Handler for this View ---
    private func handleDetailDrop(providers: [NSItemProvider]) -> Bool {
         guard let provider = providers.first else { return false }
         var collectedURL: URL? = nil
         let dispatchGroup = DispatchGroup()

         print("Handling drop for Detail View zone (Note \(midiNote))...")

         if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
             dispatchGroup.enter()
             _ = provider.loadObject(ofClass: URL.self) { url, error in
                  defer { dispatchGroup.leave() }
                   if let error = error {
                       print("    Detail Drop Error loading item: \(error)")
                       Task { @MainActor in viewModel.showError("Error reading dropped file: \(error.localizedDescription)") }
                       return
                   }

                   if let url = url, url.pathExtension.lowercased() == "wav" {
                       print("    Detail Drop: Successfully loaded WAV URL: \(url.path)")
                       collectedURL = url
                   } else if url != nil {
                       Task { @MainActor in viewModel.showError("Only single WAV files can be dropped here.") }
                   } else {
                       Task { @MainActor in viewModel.showError("Could not read the dropped file.") }
                   }
            }
         } else {
             Task { @MainActor in viewModel.showError("The dropped item was not a file.") }
             return false
         }


         dispatchGroup.notify(queue: .main) {
             if let url = collectedURL {
                 print("Detail Drop: Valid WAV file received. Requesting segmentation presentation.")
                 // --- Call the closure passed from ContentView ---
                 // Clear cache if a new file is dropped for this note
                 if self.cachedWaveformURL != url {
                     self.clearWaveformCache()
                 }
                 requestSegmentation(url, self.midiNote)
                 // ------------------------------------------------
             } else { print("Detail Drop: No valid WAV URL collected or processed.") }
         }
         return true
    }


    // --- UPDATED: Load Audio Details and Waveform Data ---
    @MainActor
    private func loadAudioFileDetails() {
        guard let sample = selectedSampleForDetails else {
            print("SampleDetailView: No sample selected/available, clearing waveform.")
            // Reset local state, but not cache
            self.audioFile = nil
            self.totalSourceFileFrames = nil
            self.waveformRMSData = []
            self.maxRMSValue = 0.001
            self.isLoadingWaveform = false // Ensure loading indicator hides
            // Trigger redraw even when clearing
            self.waveformViewID = UUID()
            return
        }

        let sourceURL = sample.sourceFileURL
        let loadingSampleID = sample.id
        print("SampleDetailView: Requesting audio details for: \(sourceURL.path) (ID: \(loadingSampleID))")

        // --- CHECK CACHE ---
        if sourceURL == cachedWaveformURL, !cachedWaveformRMSData.isEmpty, let cachedFrames = cachedTotalSourceFrames, cachedFrames > 0 {
            print("SampleDetailView: Using cached waveform data for \(sourceURL.lastPathComponent)")
            // Use cached data for local state used by waveformDisplayArea
            self.waveformRMSData = cachedWaveformRMSData
            self.totalSourceFileFrames = cachedFrames
            self.maxRMSValue = cachedMaxRMSValue
            self.isLoadingWaveform = false // Data is ready

            // Still need to potentially update scale based on cached max RMS
            let targetAmplitude: CGFloat = 0.75
            let requiredScale = (self.maxRMSValue > 0.001) ? (targetAmplitude / CGFloat(self.maxRMSValue)) : 1.0
            self.amplitudeScale = max(0.1, min(requiredScale, 50.0)) // Use state variable directly
            print("SampleDetailView: Applied cached waveform. Max RMS: \(self.maxRMSValue), Amplitude Scale: \(self.amplitudeScale)")

            // Update ID to trigger redraw with existing data but potentially new segment highlight
            self.waveformViewID = UUID()
            return // Don't reload
        }
        // --- END CACHE CHECK ---

        print("SampleDetailView: No cache hit or different file. Loading audio details and waveform for: \(sourceURL.path) (ID: \(loadingSampleID))")
        resetWaveformState() // Reset local state fully before loading
        isLoadingWaveform = true
        // Explicitly update view ID when starting a new load
        self.waveformViewID = UUID()

        Task {
            do {
                let file = try AVAudioFile(forReading: sourceURL)
                let format = file.processingFormat
                let frameCountInt64 = file.length // Keep this name for clarity

                // Temporary assignment for processing, don't assign to @State audioFile yet
                // self.audioFile = file
                // self.totalSourceFileFrames = frameCountInt64
                print("SampleDetailView: Audio info loaded. Frames: \(frameCountInt64), Sample Rate: \(format.sampleRate)")


                guard frameCountInt64 > 0 else {
                    throw NSError(domain: "AudioLoadError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Audio file has zero length."])
                }

                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCountInt64)) else {
                    throw NSError(domain: "AudioLoadError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create buffer for \(sourceURL.lastPathComponent)"])
                }
                try file.read(into: buffer)
                let frameLength = Int(buffer.frameLength)

                guard frameLength > 0 else {
                     throw NSError(domain: "AudioLoadError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Buffer frame length is zero after reading."])
                }

                guard let floatChannelData = buffer.floatChannelData else {
                     throw NSError(domain: "AudioLoadError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not get float channel data"])
                }
                // Use first channel assuming mono or taking left channel if stereo
                let channelPtr = floatChannelData[0]
                // --- Ensure buffer pointer is valid before creating UnsafeBufferPointer ---
                let audioDataCopy = [Float](UnsafeBufferPointer(start: channelPtr, count: frameLength))


                print("SampleDetailView: Copied \(audioDataCopy.count) audio samples for background processing.")

                // Define calculation parameters (adjust samplesPerPixel as needed)
                let samplesPerPixel = 1024 // Or determine based on view size? Fixed for now.
                let displaySamplesCount = max(1, frameLength / samplesPerPixel)


                // Perform RMS calculation in background task
                let calculationResult = try await Task.detached(priority: .userInitiated) {
                    var localRmsSamples = [Float](repeating: 0.0, count: displaySamplesCount)
                    var localMaxRms: Float = 0.001 // Initialize low but non-zero
                    let totalFramesInBuffer = audioDataCopy.count // Use count of the copy

                    for i in 0..<displaySamplesCount {
                        let startFrame = i * samplesPerPixel
                        // Ensure endFrame doesn't exceed the buffer size
                        let endFrame = min(startFrame + samplesPerPixel, totalFramesInBuffer)
                        let frameCountInBlock = endFrame - startFrame

                        // Ensure we have frames in the block to process
                        if frameCountInBlock > 0 {
                            var sumOfSquares: Float = 0.0
                            // Iterate safely within the bounds of audioDataCopy
                            for j in startFrame..<endFrame {
                                // Double-check index bounds (though min should handle it)
                                guard j >= 0 && j < totalFramesInBuffer else { continue }
                                let sampleValue = audioDataCopy[j]
                                sumOfSquares += sampleValue * sampleValue
                            }
                            let meanSquare = sumOfSquares / Float(frameCountInBlock)
                            let rms = sqrt(meanSquare)
                            localRmsSamples[i] = rms
                            localMaxRms = max(localMaxRms, rms) // Update max RMS found
                        } else {
                            // Handle potential case where frameCountInBlock is 0 (shouldn't happen with logic)
                            localRmsSamples[i] = 0.0
                        }
                    }
                    try Task.checkCancellation() // Allow task cancellation
                    return (samples: localRmsSamples, maxRms: localMaxRms)
                }.value


                // --- Update State & CACHE back on Main Thread ---
                // Check if the selection hasn't changed *while* loading occurred
                 guard let currentSelectedSample = self.selectedSampleForDetails,
                       currentSelectedSample.id == loadingSampleID else {
                     print("SampleDetailView: Selection changed (ID: \(self.selectedSampleForDetails?.id.uuidString ?? "nil")) while loading waveform for ID \(loadingSampleID). Discarding results.")
                     // Don't set isLoadingWaveform = false here, a new load might be in progress
                     return
                 }


                 print("SampleDetailView: Waveform RMS data extracted for \(sourceURL.lastPathComponent) (ID: \(loadingSampleID)). Display samples: \(calculationResult.samples.count)")

                // Update local state used by waveformDisplayArea
                self.waveformRMSData = calculationResult.samples
                self.totalSourceFileFrames = frameCountInt64 // Use the value from file reading
                self.maxRMSValue = max(0.001, calculationResult.maxRms) // Ensure non-zero
                self.isLoadingWaveform = false // Loading finished

                // --- UPDATE CACHE ---
                self.cachedWaveformURL = sourceURL
                self.cachedWaveformRMSData = calculationResult.samples
                self.cachedTotalSourceFrames = frameCountInt64 // Cache total frames
                self.cachedMaxRMSValue = self.maxRMSValue
                print("SampleDetailView: Cached waveform data for \(sourceURL.lastPathComponent)")
                // --- END UPDATE CACHE ---


                // Calculate and set amplitude scale
                let targetAmplitude: CGFloat = 0.75
                let requiredScale = (self.maxRMSValue > 0.001) ? (targetAmplitude / CGFloat(self.maxRMSValue)) : 1.0
                self.amplitudeScale = max(0.1, min(requiredScale, 50.0)) // Clamp scale reasonably
                print("SampleDetailView: Auto-scaling waveform. Max RMS: \(self.maxRMSValue), Initial Amplitude Scale: \(self.amplitudeScale)")

                self.waveformViewID = UUID() // Trigger redraw

            } catch {
                 // Ensure isLoading is set to false even on error
                 await MainActor.run { // Need to ensure UI updates happen on main thread
                     let errorMsg = "Error loading audio/waveform for \(sample.sourceFileURL.lastPathComponent): \(error.localizedDescription)"
                     print(errorMsg)
                     // Reset state but potentially keep cache? Or clear cache? Let's clear cache on error.
                     self.clearWaveformCache()
                     self.resetWaveformState() // Resets local state
                     self.isLoadingWaveform = false
                     self.viewModel.showError(errorMsg) // Show error to user
                     self.waveformViewID = UUID() // Trigger redraw to show error state
                 }
            }
        } // End Task
    }


    // --- Helper to Reset Waveform State ---
    @MainActor
    private func resetWaveformState() {
        // Only reset non-cached state
        audioFile = nil // Not strictly needed if not used directly
        totalSourceFileFrames = nil
        waveformRMSData = []
        maxRMSValue = 0.001
        // Keep amplitude scale, time zoom, scroll offset maybe? Or reset?
        // Let's reset them for now when loading a NEW file or clearing
        timeZoomScale = 1.0
        scrollOffset = .zero
        amplitudeScale = 1.0 // Reset amplitude scale too

        // DO NOT reset cache here, handled separately
    }

    // --- Helper to Clear Cache ---
    @MainActor
    private func clearWaveformCache() {
        print("SampleDetailView: Clearing waveform cache.")
        cachedWaveformURL = nil
        cachedWaveformRMSData = []
        cachedTotalSourceFrames = nil
        cachedMaxRMSValue = 0.001
    }



    // --- UPDATED: Waveform Drawing Function ---
    // Adjust drawWaveform to accept segment info
    private func drawWaveform(
        context: inout GraphicsContext,
        size: CGSize,
        rmsData: [Float],
        ampScale: CGFloat,
        totalSourceFrames: Int64  // Keep - Needed for X scaling
    ) {
        // *** ADD LOGGING HERE ***
        print("--- drawWaveform Called (Drawing FULL) ---")
        print("    Size: \(size)")
        print("    RMS Data Count (Full): \(rmsData.count)")
        print("    Amplitude Scale: \(ampScale)")
        // print("    Segment: \(segmentStartSample) - \(segmentEndSample) / \(totalSourceFrames)") // REMOVE
        // ************************

        let currentWaveformWidth = size.width
        // Use passed-in rmsData
        guard !rmsData.isEmpty, currentWaveformWidth > 0, size.height > 0, totalSourceFrames > 0 else {
            if size.height > 0 {
                var placeholderPath = Path()
                placeholderPath.move(to: CGPoint(x: 0, y: size.height / 2))
                placeholderPath.addLine(to: CGPoint(x: currentWaveformWidth, y: size.height / 2))
                context.stroke(placeholderPath, with: .color(.gray), lineWidth: 1)
            }
            print("DrawWaveform (Full): Skipping draw - Initial conditions not met")
            return
        }


        let halfHeight = size.height / 2
        // Use passed-in rmsData
        let fullDataCount = rmsData.count


        guard fullDataCount > 1 else {
            var flatLinePath = Path()
            flatLinePath.move(to: CGPoint(x: 0, y: halfHeight))
            flatLinePath.addLine(to: CGPoint(x: currentWaveformWidth, y: halfHeight))
            context.stroke(flatLinePath, with: .color(.accentColor.opacity(0.6)), lineWidth: 1)
            print("DrawWaveform (Full): Skipping draw - dataCount <= 1") // Add log here too
            return
        }

        let path = Path { p in
            var hasMoved = false
             // Loop over ALL indices
            for i in 0..<fullDataCount { // REVERT LOOP
                // Calculate the frame corresponding to this RMS sample index
                let frameRatio = (fullDataCount > 1) ? Double(i) / Double(fullDataCount - 1) : 0.0
                let approxFrame = frameRatio * Double(totalSourceFrames)

                // Calculate the X position based on the frame's ratio to total frames relative to the canvas width
                let normalizedX = approxFrame / Double(totalSourceFrames)
                let xPosition = normalizedX * size.width // Position within the full view width

                // Use passed-in rmsData safely
                guard i >= 0 && i < rmsData.count else { continue }
                let rmsValue = CGFloat(rmsData[i])

                // Use passed-in ampScale
                let safeAmplitudeScale = max(0.01, ampScale)
                // Calculate the amplitude offset based on scaling and halfHeight
                let amplitudeOffset = rmsValue * safeAmplitudeScale * halfHeight // Scale RMS relative to halfHeight

                // Calculate yTop and yBottom centered around halfHeight
                let yTop = max(0, halfHeight - amplitudeOffset)
                let yBottom = min(size.height, halfHeight + amplitudeOffset)


                if !hasMoved {
                    p.move(to: CGPoint(x: xPosition, y: yTop))
                    hasMoved = true
                } else {
                    // Ensure lineTo doesn't introduce visual gaps if amplitude is zero
                    p.addLine(to: CGPoint(x: xPosition, y: yTop))
                }

                // Only draw vertical line if amplitude > 0 and yBottom > yTop
                if amplitudeOffset > 0 && yBottom > yTop {
                    p.addLine(to: CGPoint(x: xPosition, y: yBottom))
                    // Go back to yTop to prepare for the next point's top line segment
                    // This creates the filled "envelope" shape when stroked.
                    p.addLine(to: CGPoint(x: xPosition, y: yTop))
                }
            }
        }
        // Draw with standard accent color/opacity
        context.stroke(path, with: .color(.accentColor.opacity(0.6)), lineWidth: 1)
    }


    private func drawSegmentHighlight(
        context: inout GraphicsContext,
        size: CGSize,
        totalContentWidth: CGFloat, // This is the potentially zoomed width
        segmentStartSample: Int64,
        segmentEndSample: Int64,
        totalSourceFrames: Int64
    ) {
        // Log the values received
        print("DrawSegmentHighlight: Drawing highlight from \(segmentStartSample) to \(segmentEndSample) (Total: \(totalSourceFrames))")

        guard totalSourceFrames > 0, size.width > 0, size.height > 0, totalContentWidth > 0 else {
            print("DrawSegmentHighlight: Skipping draw - Conditions not met (Size: \(size), totalContentWidth: \(totalContentWidth))")
            return
        }
        guard segmentEndSample > segmentStartSample else {
            print("DrawSegmentHighlight: Skipping draw - Invalid segment (end <= start)")
            return
        }

        // Calculate positions based on the total *content* width (which includes zoom)
        let startRatio = Double(segmentStartSample) / Double(totalSourceFrames)
        let endRatio = Double(segmentEndSample) / Double(totalSourceFrames)

        let startX = max(0, startRatio * totalContentWidth) // Position within the scrollable content
        let endX = min(totalContentWidth, endRatio * totalContentWidth) // Position within the scrollable content
        let segmentWidthInContent = max(1, endX - startX)

        // Draw the highlight rectangle
        let highlightRect = CGRect(x: startX, y: 0, width: segmentWidthInContent, height: size.height)
        let highlightPath = Path(highlightRect)

        // Fill the highlight area
        context.fill(highlightPath, with: .color(.accentColor.opacity(0.4)))

        // Draw vertical lines at the start and end of the segment
        var startLine = Path()
        startLine.move(to: CGPoint(x: startX, y: 0))
        startLine.addLine(to: CGPoint(x: startX, y: size.height))
        context.stroke(startLine, with: .color(.white.opacity(0.7)), lineWidth: 1.5)

        var endLine = Path()
        endLine.move(to: CGPoint(x: endX, y: 0))
        endLine.addLine(to: CGPoint(x: endX, y: size.height))
        context.stroke(endLine, with: .color(.white.opacity(0.7)), lineWidth: 1.5)
    }


    // --- Extracted Waveform Display Area (Pass sample) ---
    @ViewBuilder
    private func waveformDisplayArea(sampleToDisplay: MultiSamplePartData) -> some View { // Accept sample
        // Use the passed sample for segment info
        let currentSegmentStart = sampleToDisplay.segmentStartSample
        let currentSegmentEnd = sampleToDisplay.segmentEndSample

        if isLoadingWaveform {
             VStack {
                 ProgressView()
                 Text("Loading Waveform...").font(.caption).foregroundColor(.secondary)
             }
             .frame(height: 150).frame(maxWidth: .infinity)
             .background(Color.secondary.opacity(0.1)).cornerRadius(5)
        // Use cached total frames if available, otherwise indicate loading/error
        } else if !waveformRMSData.isEmpty, let totalFrames = self.totalSourceFileFrames, totalFrames > 0 {
            HStack(alignment: .center, spacing: 5) {
                VStack { // VStack for waveform + time zoom slider
                    GeometryReader { geometry in
                        // Calculate total width based on zoom AFTER getting geometry size
                        let currentVisibleWidth = geometry.size.width
                        let totalContentWidth = currentVisibleWidth * timeZoomScale

                        ScrollViewReader { scrollProxy in
                            ScrollView(.horizontal, showsIndicators: true) {
                                 ZStack(alignment: .leading) {
                                    // Explicitly capture necessary state for the Canvas
                                    // Capture segment info from the sampleToDisplay parameter
                                    Canvas { [waveformRMSData, amplitudeScale, timeZoomScale, totalFrames, currentSegmentStart, currentSegmentEnd] context, size in
                                        // 1. Draw the full waveform
                                        drawWaveform(
                                            context: &context,
                                            size: size,
                                            rmsData: waveformRMSData,
                                            ampScale: amplitudeScale,
                                            totalSourceFrames: totalFrames           // Keep
                                        )
                                         // 2. Draw the segment highlight on top
                                         drawSegmentHighlight(
                                             context: &context, size: size,
                                             totalContentWidth: totalContentWidth, // Pass calculated total width
                                             segmentStartSample: currentSegmentStart,
                                             segmentEndSample: currentSegmentEnd,
                                             totalSourceFrames: totalFrames
                                         )
                                    }
                                    .id(waveformViewID) // Keep the ID change
                                    // Frame uses calculated totalContentWidth for scrolling
                                    .frame(width: totalContentWidth, height: geometry.size.height)
                                 } // End ZStack
                                 .background(GeometryReader { geo in
                                      Color.clear.preference(key: ScrollOffsetPreferenceKey.self,
                                                            value: geo.frame(in: .named("detailScrollView")).origin)
                                  })
                            } // End ScrollView
                            .coordinateSpace(name: "detailScrollView")
                            .scrollDisabled(timeZoomScale <= 1.0)
                            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
                                self.scrollOffset = newOffset
                            }
                        } // End ScrollViewReader
                    } // End GeometryReader for Waveform Canvas

                    // --- Horizontal Time Zoom Slider ---
                    HStack {
                        Text("Zoom:")
                        Slider(value: $timeZoomScale, in: 1.0...20.0)
                        Text(String(format: "%.1fx", timeZoomScale))
                    }
                    .padding(.top, 5)
                    .disabled(isLoadingWaveform || waveformRMSData.isEmpty)

                } // End VStack for waveform + time zoom
                .frame(height: 150)
                .clipped()

                // --- Vertical Amplitude Slider ---
                // Ensure max scale calculation handles maxRMSValue potentially being zero or very small
                let maxVerticalScale = max(1.0, 50.0 / max(CGFloat(maxRMSValue), 0.01))
                Slider(value: $amplitudeScale, in: 0.1...maxVerticalScale)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 150, height: 20) // Adjust frame for vertical slider
                    .padding(.vertical) // Add padding around vertical slider
                    .disabled(isLoadingWaveform || waveformRMSData.isEmpty)


            } // End HStack for waveform area + amplitude slider
            .padding(.horizontal)

        } else {
             VStack {
                 Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                 // Provide more specific feedback based on state
                 if waveformRMSData.isEmpty && !isLoadingWaveform {
                     Text("No waveform data available.").font(.caption).foregroundColor(.secondary)
                 } else {
                     Text("Could not load waveform.").font(.caption).foregroundColor(.secondary)
                 }
             }
             .frame(height: 150).frame(maxWidth: .infinity)
             .background(Color.secondary.opacity(0.1)).cornerRadius(5)
        }
    }
}

// --- Preview ---
// Update Preview to reflect current structure
#Preview {
    // Create some dummy sample data for the preview
    let dummyFileURL = URL(fileURLWithPath: "/path/to/dummy/sample.wav") // Use a placeholder path

    // Velocity Zones Example
    let sample1 = MultiSamplePartData(
        name: "Sample Low Vel", keyRangeMin: 60, keyRangeMax: 60,
        velocityRange: VelocityRangeData(min: 0, max: 63, crossfadeMin: 0, crossfadeMax: 63),
        sourceFileURL: dummyFileURL, segmentStartSample: 1000, segmentEndSample: 50000,
        absolutePath: dummyFileURL.path, originalAbsolutePath: dummyFileURL.path,
        sampleRate: 44100, fileSize: 102400, lastModDate: Date(), originalFileFrameCount: 100000
    )
    let sample2 = MultiSamplePartData(
        name: "Sample High Vel", keyRangeMin: 60, keyRangeMax: 60,
        velocityRange: VelocityRangeData(min: 64, max: 127, crossfadeMin: 64, crossfadeMax: 127),
        sourceFileURL: dummyFileURL, segmentStartSample: 60000, segmentEndSample: 90000,
        absolutePath: dummyFileURL.path, originalAbsolutePath: dummyFileURL.path,
        sampleRate: 44100, fileSize: 102400, lastModDate: Date(), originalFileFrameCount: 100000
    )

    // Round Robin Example (Create separate view or use toggle in preview)
    let rrSample1 = MultiSamplePartData(
        name: "RR Sample 1", keyRangeMin: 61, keyRangeMax: 61, // Different note for separate preview
        velocityRange: VelocityRangeData(min: 0, max: 127, crossfadeMin: 0, crossfadeMax: 127),
        sourceFileURL: URL(fileURLWithPath: "/path/to/rr1.wav"), segmentStartSample: 100, segmentEndSample: 10000,
        absolutePath: "/path/to/rr1.wav", originalAbsolutePath: "/path/to/rr1.wav",
        sampleRate: 44100, fileSize: 10240, lastModDate: Date(), originalFileFrameCount: 20000
    )
     let rrSample2 = MultiSamplePartData(
        name: "RR Sample 2", keyRangeMin: 61, keyRangeMax: 61,
        velocityRange: VelocityRangeData(min: 0, max: 127, crossfadeMin: 0, crossfadeMax: 127),
        sourceFileURL: URL(fileURLWithPath: "/path/to/rr2.wav"), segmentStartSample: 200, segmentEndSample: 15000, // Different segment
        absolutePath: "/path/to/rr2.wav", originalAbsolutePath: "/path/to/rr2.wav",
        sampleRate: 44100, fileSize: 12240, lastModDate: Date(), originalFileFrameCount: 25000
    )


    // Use a Group or TabView to show both scenarios in Preview
    Group {
        // Velocity Zones Preview
        SampleDetailView(midiNote: 60) { url, note in
            print("Preview (Vel): Request segmentation for \(url.lastPathComponent) on note \(note)")
        }
        .previewDisplayName("Velocity Zones")
        .padding()

        // Round Robins Preview (Using same dummy URL for preview simplicity)
        // NOTE: The old preview passed [rrPreviewSample1, rrPreviewSample2]. This logic is now 
        // handled internally by the view using the ViewModel. This preview will appear empty initially.
        SampleDetailView(midiNote: 61) { url, note in
            print("Preview (RR): Request segmentation for \(url.lastPathComponent) on note \(note)")
        }
        .previewDisplayName("Round Robins")
        .padding()

         // Empty State Preview
         SampleDetailView(midiNote: 62) { url, note in
             print("Preview (Empty): Request segmentation for \(url.lastPathComponent) on note \(note)")
         }
         .previewDisplayName("Empty")
         .padding()
    }
    .environmentObject(SamplerViewModel()) // Provide a dummy ViewModel once for the Group
    .previewLayout(.sizeThatFits)
}
