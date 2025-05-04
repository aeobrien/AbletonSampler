import SwiftUI

struct SampleMappingGridView: View {
    let layers: [VelocityLayer]
    @Binding var selectedSlot: SelectedSlot? // Input binding for selection
    
    // Constants for layout
    private let totalVelocityRange: CGFloat = 128.0 // 0-127
    private let gridBorderColor = Color.gray.opacity(0.5)
    private let occupiedSlotColor = Color.blue.opacity(0.6)
    private let emptySlotColor = Color.gray.opacity(0.2)
    private let gridSpacing: CGFloat = 1.0 // Spacing between cells
    private let selectedBorderColor = Color.yellow
    private let selectedBorderWidth: CGFloat = 2.0
    
    var body: some View {
        GeometryReader { geometry in
            let totalGridWidth = geometry.size.width
            let totalGridHeight = geometry.size.height
            
            // --- Debugging: Print Geometry --- 
            // let _ = print("Grid Geometry: W=\(totalGridWidth), H=\(totalGridHeight)")
            // ---------------------------------
            
            if layers.isEmpty {
                // Display a message if there are no layers
                Text("No sample layers defined for this key.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.1))
            } else {
                // Main grid layout: VStack for layers (Y-axis: Velocity)
                VStack(alignment: .leading, spacing: gridSpacing) {
                    // Iterate through layers, sorted by velocity (assuming they are pre-sorted)
                    ForEach(layers) { layer in
                        // Calculate height for this layer based on its velocity range
                        let layerHeight = calculateLayerHeight(layer: layer, totalGridHeight: totalGridHeight)
                        
                        // HStack for round robin slots within the layer (X-axis: Round Robins)
                        HStack(spacing: gridSpacing) {
                            // Check if the layer has any sample slots defined
                            if layer.roundRobinCount > 0 {
                                // Calculate width for each slot in this layer
                                let slotWidth = calculateSlotWidth(layer: layer, totalGridWidth: totalGridWidth)
                                
                                // Iterate through the sample slots (using indices)
                                ForEach(0..<layer.roundRobinCount, id: \.self) { rrIndex in
                                    let sample = layer.samples[rrIndex]
                                    // Determine if this slot is the currently selected one
                                    let isSelected = selectedSlot?.layerId == layer.id && selectedSlot?.rrIndex == rrIndex
                                    
                                    // --- Cell View --- 
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(sample != nil ? occupiedSlotColor : emptySlotColor)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 2)
                                                // Show yellow border if selected, otherwise normal grid border
                                                .stroke(isSelected ? selectedBorderColor : gridBorderColor, 
                                                        lineWidth: isSelected ? selectedBorderWidth : 1)
                                        )
                                        .frame(width: slotWidth, height: layerHeight)
                                        // --- Add tap gesture --- 
                                        .onTapGesture {
                                            let tappedSlot = SelectedSlot(layerId: layer.id, rrIndex: rrIndex)
                                            // Toggle selection: if tapping the already selected slot, deselect. Otherwise, select.
                                            if selectedSlot == tappedSlot {
                                                selectedSlot = nil 
                                            } else {
                                                selectedSlot = tappedSlot
                                            }
                                            print("Tapped Layer ID: \(layer.id), RR Index: \(rrIndex). Selected: \(selectedSlot)")
                                        }
                                } 
                            } else {
                                // If a layer exists but has zero RR slots (shouldn't happen ideally)
                                // Draw a placeholder for the layer's full width
                                Rectangle()
                                    .fill(emptySlotColor)
                                     .overlay(
                                        Rectangle().stroke(gridBorderColor, lineWidth: 1)
                                     )
                                    .frame(height: layerHeight)
                                Text("Layer defined but no RR slots") // Debug text
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(height: layerHeight) // Set the height for the HStack (layer)
                    }
                    
                    Spacer(minLength: 0) // Push layers to the top if they don't fill height
                    
                }
                .frame(width: totalGridWidth, height: totalGridHeight) // Constrain VStack size
                // .background(Color.yellow.opacity(0.2)) // Optional background for debugging VStack area
                .clipped() // Clip the contents to the bounds
            }
        }
        // Add a border around the whole grid area for clarity
        .border(gridBorderColor, width: 1)
    }
    
    // --- Helper Functions --- 
    
    private func calculateLayerHeight(layer: VelocityLayer, totalGridHeight: CGFloat) -> CGFloat {
        // Ensure velocity max is >= min 
        let velocitySpan = max(0, layer.velocityRange.max - layer.velocityRange.min + 1)
        // Calculate proportion of the total velocity range (0-127)
        let heightProportion = CGFloat(velocitySpan) / totalVelocityRange
        // Calculate actual height, subtracting spacing for all but the last layer (handled by VStack spacing)
        let calculatedHeight = max(gridSpacing * 2, heightProportion * totalGridHeight) // Ensure minimum visible height
        
        // --- Debugging: Print Height Calc --- 
        // print(" Layer ID: \(layer.id), Vel Range: \(layer.velocityRange.min)-\(layer.velocityRange.max), Span: \(velocitySpan), Proportion: \(heightProportion), GridH: \(totalGridHeight), Calc H: \(calculatedHeight)")
        // ------------------------------------
        
        return calculatedHeight
    }
    
    private func calculateSlotWidth(layer: VelocityLayer, totalGridWidth: CGFloat) -> CGFloat {
        guard layer.roundRobinCount > 0 else { 
            // print("Warning: Calculating slot width for layer with 0 RR count. Returning full width.")
            return totalGridWidth // Or 0? Let's return full width for now.
        }
        let totalSpacing = gridSpacing * CGFloat(max(0, layer.roundRobinCount - 1))
        let availableWidth = totalGridWidth - totalSpacing
        let width = max(gridSpacing * 2, availableWidth / CGFloat(layer.roundRobinCount)) // Ensure minimum visible width
        
        // --- Debugging: Print Width Calc --- 
        // print(" Layer ID: \(layer.id), RR Count: \(layer.roundRobinCount), GridW: \(totalGridWidth), Spacing: \(totalSpacing), AvailW: \(availableWidth), Calc W: \(width)")
        // ------------------------------------
        return width
    }
}

// --- Preview Provider --- 

// Create some dummy sample data for the preview
private let dummyFileURL = URL(fileURLWithPath: "/path/to/dummy/sample.wav")
// --- CORRECTED Initializers for MultiSamplePartData (Based on new errors) ---
private let dummySample1 = MultiSamplePartData(
    name: "Soft Hit", 
    keyRangeMin: 0, keyRangeMax: 127, // Added
    velocityRange: VelocityRangeData(min: 0, max: 40, crossfadeMin: 0, crossfadeMax: 40), // Added + Corrected VelocityRangeData init
    sourceFileURL: dummyFileURL,
    segmentStartSample: 100, segmentEndSample: 10000,
    absolutePath: dummyFileURL.path, // Added
    originalAbsolutePath: dummyFileURL.path, // Added
    sampleRate: 44100, fileSize: 12345, lastModDate: Date(), originalFileFrameCount: 50000 // Assuming these are okay
)
private let dummySample2 = MultiSamplePartData(
    name: "Medium Hit 1", 
    keyRangeMin: 0, keyRangeMax: 127,
    velocityRange: VelocityRangeData(min: 41, max: 90, crossfadeMin: 41, crossfadeMax: 90), // Added + Corrected VelocityRangeData init
    sourceFileURL: dummyFileURL,
    segmentStartSample: 11000, segmentEndSample: 30000,
    absolutePath: dummyFileURL.path,
    originalAbsolutePath: dummyFileURL.path,
    sampleRate: 44100, fileSize: 12345, lastModDate: Date(), originalFileFrameCount: 50000
)
private let dummySample3 = MultiSamplePartData(
    name: "Medium Hit 2", 
    keyRangeMin: 0, keyRangeMax: 127,
    velocityRange: VelocityRangeData(min: 41, max: 90, crossfadeMin: 41, crossfadeMax: 90), // Added + Corrected VelocityRangeData init
    sourceFileURL: dummyFileURL,
    segmentStartSample: 31000, segmentEndSample: 50000,
    absolutePath: dummyFileURL.path,
    originalAbsolutePath: dummyFileURL.path,
    sampleRate: 44100, fileSize: 12345, lastModDate: Date(), originalFileFrameCount: 50000
)
private let dummySample4 = MultiSamplePartData(
    name: "Loud Hit", 
    keyRangeMin: 0, keyRangeMax: 127,
    velocityRange: VelocityRangeData(min: 91, max: 127, crossfadeMin: 91, crossfadeMax: 127), // Added + Corrected VelocityRangeData init
    sourceFileURL: dummyFileURL,
    segmentStartSample: 55000, segmentEndSample: 80000,
    absolutePath: dummyFileURL.path,
    originalAbsolutePath: dummyFileURL.path,
    sampleRate: 44100, fileSize: 12345, lastModDate: Date(), originalFileFrameCount: 50000
)
// --- END CORRECTION ---

// Create dummy layers for the preview
private let previewLayers: [VelocityLayer] = [
    // Layer 1: 0-40, 2 RR slots (one empty)
    VelocityLayer(
        // --- CORRECTED VelocityRangeData init ---
        velocityRange: VelocityRangeData(min: 0, max: 40, crossfadeMin: 0, crossfadeMax: 40),
        samples: [dummySample1, nil]
    ),
    // Layer 2: 41-90, 3 RR slots (two filled)
    VelocityLayer(
        // --- CORRECTED VelocityRangeData init ---
        velocityRange: VelocityRangeData(min: 41, max: 90, crossfadeMin: 41, crossfadeMax: 90),
        samples: [dummySample2, dummySample3, nil] 
    ),
    // Layer 3: 91-127, 1 RR slot (filled)
    VelocityLayer(
        // --- CORRECTED VelocityRangeData init ---
        velocityRange: VelocityRangeData(min: 91, max: 127, crossfadeMin: 91, crossfadeMax: 127),
        samples: [dummySample4]
    )
]

private let emptyPreviewLayers: [VelocityLayer] = []

private let singleFullLayer: [VelocityLayer] = [
    VelocityLayer(
        // --- CORRECTED VelocityRangeData init ---
        velocityRange: VelocityRangeData(min: 0, max: 127, crossfadeMin: 0, crossfadeMax: 127),
        samples: [dummySample1]
    )
]

// --- Wrapper View for Previews to Manage State --- 
struct SampleMappingGridPreviewWrapper: View {
    @State private var selectedSlot: SelectedSlot? = nil
    let layers: [VelocityLayer]
    
    var body: some View {
        VStack {
            Text("Selected Slot: \(selectedSlotDescription)")
                .padding(.bottom)
            SampleMappingGridView(layers: layers, selectedSlot: $selectedSlot)
        }
    }
    
    var selectedSlotDescription: String {
        if let slot = selectedSlot {
            // Find layer name for context if needed (optional)
            let layerVel = layers.first { $0.id == slot.layerId }?.velocityRange
            let velString = layerVel != nil ? "Vel \(layerVel!.min)-\(layerVel!.max)" : "Layer ID \(slot.layerId.uuidString.prefix(4))"
            return "\(velString), RR Index \(slot.rrIndex)"
        } else {
            return "None"
        }
    }
}

// --- Updated Previews to use the Wrapper --- 

#Preview("Standard Layers") {
    SampleMappingGridPreviewWrapper(layers: previewLayers)
        .frame(width: 300, height: 250) // Adjusted height for text
        .padding()
}

#Preview("Empty Layers") {
    // Selection doesn't apply here, but use wrapper for consistency
    SampleMappingGridPreviewWrapper(layers: emptyPreviewLayers)
        .frame(width: 300, height: 250)
        .padding()
}

#Preview("Single Full Layer") {
    SampleMappingGridPreviewWrapper(layers: singleFullLayer)
        .frame(width: 300, height: 250)
        .padding()
}

#Preview("Single Layer, 5 RR") {
    SampleMappingGridPreviewWrapper(layers: [
        VelocityLayer(
            velocityRange: VelocityRangeData(min: 0, max: 127, crossfadeMin: 0, crossfadeMax: 127),
            samples: [dummySample1, dummySample2, nil, dummySample3, dummySample4]
        )
    ])
    .frame(width: 400, height: 200) // Adjusted height
    .padding()
}

#Preview("Multiple Layers, Varying RR") {
    SampleMappingGridPreviewWrapper(layers: [
        VelocityLayer(velocityRange: VelocityRangeData(min: 0, max: 31, crossfadeMin: 0, crossfadeMax: 31), samples: [dummySample1]),
        VelocityLayer(velocityRange: VelocityRangeData(min: 32, max: 63, crossfadeMin: 32, crossfadeMax: 63), samples: [dummySample2, nil, dummySample3]),
        VelocityLayer(velocityRange: VelocityRangeData(min: 64, max: 95, crossfadeMin: 64, crossfadeMax: 95), samples: [nil, nil]),
        VelocityLayer(velocityRange: VelocityRangeData(min: 96, max: 127, crossfadeMin: 96, crossfadeMax: 127), samples: [dummySample4, nil])
    ])
    .frame(width: 350, height: 300) // Adjusted height
    .padding()
} 