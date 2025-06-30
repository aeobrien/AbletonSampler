import Foundation

// MARK: - TransientGroup Data Model

/// Represents a velocity range
struct VelocityRange: Codable {
    var min: Int
    var max: Int
}

/// Represents a group of transients within an audio file that will be mapped together
struct TransientGroup: Identifiable, Codable {
    let id: UUID
    var name: String
    var color: String // Hex color for visualization
    
    // Audio region
    var startFrame: Int64
    var endFrame: Int64
    
    // Mapping configuration
    var velocityLayers: Int = 1
    var roundRobins: Int = 1
    
    // Assignment
    var targetMidiNote: Int?
    var targetVelocityRange: VelocityRange?
    
    // Transient markers within this group
    var transients: [TransientMarker] = []
    
    /// Computed property to get the total number of segments expected
    var expectedSegments: Int {
        return velocityLayers * roundRobins
    }
    
    /// Check if the group has the correct number of transients
    var isComplete: Bool {
        return transients.count == expectedSegments
    }
}

/// Represents a single transient marker within a group
struct TransientMarker: Identifiable, Codable {
    let id: UUID
    var framePosition: Int64
    var velocityLayer: Int // 0-based index
    var roundRobinIndex: Int // 0-based index
    
    // Optional: detected amplitude for auto-velocity assignment
    var detectedAmplitude: Float?
    
    init(id: UUID = UUID(), framePosition: Int64, velocityLayer: Int, roundRobinIndex: Int, detectedAmplitude: Float? = nil) {
        self.id = id
        self.framePosition = framePosition
        self.velocityLayer = velocityLayer
        self.roundRobinIndex = roundRobinIndex
        self.detectedAmplitude = detectedAmplitude
    }
}

// MARK: - Group Management

/// Manages transient groups for a specific audio file
class TransientGroupManager: ObservableObject {
    @Published var groups: [TransientGroup] = []
    @Published var selectedGroupId: UUID?
    
    // Audio file reference
    var audioFileURL: URL?
    var totalFrames: Int64 = 0
    var sampleRate: Double = 44100
    
    // Color palette for groups
    private let colorPalette = [
        "#FF6B6B", // Red
        "#4ECDC4", // Teal
        "#45B7D1", // Blue
        "#96CEB4", // Green
        "#FECA57", // Yellow
        "#DDA0DD", // Plum
        "#F8B500", // Orange
        "#B983FF"  // Purple
    ]
    
    /// Creates a new group with automatic color assignment
    func createGroup(name: String? = nil, startFrame: Int64, endFrame: Int64) -> TransientGroup {
        let groupNumber = groups.count + 1
        let groupName = name ?? "Group \(groupNumber)"
        let color = colorPalette[groups.count % colorPalette.count]
        
        let group = TransientGroup(
            id: UUID(),
            name: groupName,
            color: color,
            startFrame: startFrame,
            endFrame: endFrame,
            velocityLayers: 1,
            roundRobins: 1,
            targetMidiNote: nil,
            targetVelocityRange: nil,
            transients: []
        )
        
        groups.append(group)
        selectedGroupId = group.id
        return group
    }
    
    /// Deletes a group
    func deleteGroup(_ groupId: UUID) {
        groups.removeAll { $0.id == groupId }
        if selectedGroupId == groupId {
            selectedGroupId = groups.first?.id
        }
    }
    
    /// Updates a group
    func updateGroup(_ group: TransientGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        }
    }
    
    /// Adds a transient marker to a group
    func addTransient(to groupId: UUID, at framePosition: Int64) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else { return }
        
        let group = groups[groupIndex]
        let existingCount = group.transients.count
        
        // Auto-assign to next available slot
        let velocityLayer = existingCount / group.roundRobins
        let roundRobinIndex = existingCount % group.roundRobins
        
        let transient = TransientMarker(
            framePosition: framePosition,
            velocityLayer: velocityLayer,
            roundRobinIndex: roundRobinIndex
        )
        
        groups[groupIndex].transients.append(transient)
    }
    
    /// Removes a transient marker
    func removeTransient(from groupId: UUID, transientId: UUID) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[groupIndex].transients.removeAll { $0.id == transientId }
    }
    
    /// Auto-detects transients within a group's region using RMS-based detection
    func autoDetectTransients(for groupId: UUID, audioData: [Float], threshold: Float = 0.1, samplesPerDataPoint: Int = 1) {
        guard let group = groups.first(where: { $0.id == groupId }) else { return }
        guard audioData.count > 1 else { 
            print("Audio data too short for transient detection")
            return 
        }
        
        var transientIndices: [Int] = []
        let dataCount = audioData.count
        let minEnergyThreshold: Float = 0.005
        
        // Calculate differences between consecutive RMS values
        var differences: [Float] = []
        differences.reserveCapacity(dataCount - 1)
        for i in 0..<(dataCount - 1) {
            let diff = abs(audioData[i+1] - audioData[i])
            differences.append(diff)
        }
        
        // Find the maximum difference for normalization
        guard let maxDifference = differences.max(), maxDifference > Float.ulpOfOne else {
            print("No significant differences found in data for group \(group.name)")
            return
        }
        
        print("Max difference in group \(group.name): \(maxDifference)")
        
        // Detect peaks in the differences that exceed the threshold
        for i in 0..<differences.count {
            let normalizedDiff = differences[i] / maxDifference
            
            if normalizedDiff > threshold && audioData[i+1] > minEnergyThreshold {
                let detectedIndex = i
                
                // Simple debounce
                let minIndexDistance: Int = 2
                if let lastIndex = transientIndices.last {
                    if (detectedIndex - lastIndex) < minIndexDistance {
                        continue
                    }
                }
                transientIndices.append(detectedIndex)
            }
        }
        
        print("Detected \(transientIndices.count) transients in group \(group.name)")
        
        // Clear existing transients and add ALL detected ones (not limited by expectedSegments)
        if let groupIndex = groups.firstIndex(where: { $0.id == groupId }) {
            groups[groupIndex].transients.removeAll()
            
            // Add all detected transients, automatically assigning to velocity layers and round robins
            for (index, transientIndex) in transientIndices.enumerated() {
                let velocityLayer = index / group.roundRobins
                let roundRobinIndex = index % group.roundRobins
                
                // If we have more transients than expected slots, wrap around
                let wrappedVelocityLayer = velocityLayer % group.velocityLayers
                
                // Convert data index to frame position
                let frameOffset = Int64(transientIndex * samplesPerDataPoint)
                
                let transient = TransientMarker(
                    framePosition: group.startFrame + frameOffset,
                    velocityLayer: wrappedVelocityLayer,
                    roundRobinIndex: roundRobinIndex,
                    detectedAmplitude: nil
                )
                
                groups[groupIndex].transients.append(transient)
            }
            
            print("Group now has \(groups[groupIndex].transients.count) transients")
        }
    }
    
    /// Sorts transients within a group by frame position
    func sortTransients(in groupId: UUID) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[groupIndex].transients.sort { $0.framePosition < $1.framePosition }
        
        // Re-assign velocity layers and round robins based on order
        for (index, transient) in groups[groupIndex].transients.enumerated() {
            let velocityLayer = index / groups[groupIndex].roundRobins
            let roundRobinIndex = index % groups[groupIndex].roundRobins
            
            groups[groupIndex].transients[index] = TransientMarker(
                id: transient.id,
                framePosition: transient.framePosition,
                velocityLayer: velocityLayer,
                roundRobinIndex: roundRobinIndex,
                detectedAmplitude: transient.detectedAmplitude
            )
        }
    }
    
    /// Generates sample segments from groups for export
    func generateSegments() -> [(group: TransientGroup, segments: [SampleSegment])] {
        var results: [(group: TransientGroup, segments: [SampleSegment])] = []
        
        for group in groups {
            var segments: [SampleSegment] = []
            
            // Sort transients by position
            let sortedTransients = group.transients.sorted { $0.framePosition < $1.framePosition }
            
            for (index, transient) in sortedTransients.enumerated() {
                // Determine segment end (next transient or group end)
                let segmentEnd: Int64
                if index < sortedTransients.count - 1 {
                    segmentEnd = sortedTransients[index + 1].framePosition - 1
                } else {
                    segmentEnd = group.endFrame
                }
                
                let segment = SampleSegment(
                    startFrame: transient.framePosition,
                    endFrame: segmentEnd,
                    velocityLayer: transient.velocityLayer,
                    roundRobinIndex: transient.roundRobinIndex,
                    midiNote: group.targetMidiNote,
                    velocityRange: group.targetVelocityRange
                )
                
                segments.append(segment)
            }
            
            results.append((group: group, segments: segments))
        }
        
        return results
    }
}

/// Represents a sample segment ready for export
struct SampleSegment {
    let startFrame: Int64
    let endFrame: Int64
    let velocityLayer: Int
    let roundRobinIndex: Int
    let midiNote: Int?
    let velocityRange: VelocityRange?
}