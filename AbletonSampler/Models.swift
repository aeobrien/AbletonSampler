import Foundation

// Represents a velocity zone within a key map
struct VelocityLayer: Identifiable, Hashable {
    let id = UUID() // Unique ID for the layer
    var velocityRange: VelocityRangeData
    var samples: [MultiSamplePartData?] // Array for round robins, nil means empty slot

    // Conformance to Hashable (needed if used in certain SwiftUI views/collections)
    // Only hash based on ID, as range/samples can change
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Conformance to Equatable (based on ID)
    static func == (lhs: VelocityLayer, rhs: VelocityLayer) -> Bool {
        lhs.id == rhs.id
    }

    // Helper to get the number of active samples (non-nil)
    var activeSampleCount: Int {
        samples.compactMap { $0 }.count
    }

    // Helper to get the total number of slots (for RR calculation)
    var roundRobinCount: Int {
        samples.count // Returns the total number of slots (including nils)
    }
    
    // Helper to check if the layer contains any actual samples
    var isEmpty: Bool {
        return activeSampleCount == 0
    }
}

// Represents the indices of a selected slot in the SampleMappingGridView
struct SelectedSlot: Hashable, Equatable {
    let layerId: VelocityLayer.ID // Use the layer's stable ID
    let rrIndex: Int // The index within the layer's samples array
} 