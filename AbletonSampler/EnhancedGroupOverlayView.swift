import SwiftUI

struct EnhancedGroupOverlayView: View {
    let group: TransientGroup
    let geometry: GeometryProxy
    let visibleSamples: Range<Int64>
    let totalFrames: Int64
    let isSelected: Bool
    @ObservedObject var groupManager: TransientGroupManager
    
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingTransient: UUID? = nil
    @State private var dragOffset: CGFloat = 0
    
    private var color: Color {
        Color(group.color) ?? .blue
    }
    
    var body: some View {
        if totalFrames > 0 {
            let groupStartSample = group.startFrame
            let groupEndSample = group.endFrame
            
            // Check if the group overlaps with the visible range
            let groupRange = groupStartSample..<groupEndSample
            if visibleSamples.overlaps(groupRange) {
                let clampedStart = max(groupStartSample, visibleSamples.lowerBound)
                let clampedEnd = min(groupEndSample, visibleSamples.upperBound)
                
                let startX = CGFloat(clampedStart - visibleSamples.lowerBound) / CGFloat(visibleSamples.count) * geometry.size.width
                let endX = CGFloat(clampedEnd - visibleSamples.lowerBound) / CGFloat(visibleSamples.count) * geometry.size.width
                let rectWidth = endX - startX
                
                ZStack(alignment: .leading) {
                    // Group background and border
                    Rectangle()
                        .fill(color.opacity(isSelected ? 0.3 : 0.2))
                        .frame(width: rectWidth, height: geometry.size.height)
                        .offset(x: startX)
                    
                    Rectangle()
                        .stroke(color, lineWidth: isSelected ? 2 : 1)
                        .frame(width: rectWidth, height: geometry.size.height)
                        .offset(x: startX)
                    
                    // Selection handles (only when selected)
                    if isSelected {
                        // Start handle
                        if clampedStart == groupStartSample {
                            SelectionHandle(
                                position: startX,
                                height: geometry.size.height,
                                isDragging: $isDraggingStart,
                                onDrag: { delta in
                                    updateGroupStart(delta: delta)
                                }
                            )
                        }
                        
                        // End handle
                        if clampedEnd == groupEndSample {
                            SelectionHandle(
                                position: endX,
                                height: geometry.size.height,
                                isDragging: $isDraggingEnd,
                                onDrag: { delta in
                                    updateGroupEnd(delta: delta)
                                }
                            )
                        }
                        
                        // Transient markers
                        ForEach(group.transients) { transient in
                            if visibleSamples.contains(transient.framePosition) {
                                let transientX = CGFloat(transient.framePosition - visibleSamples.lowerBound) / CGFloat(visibleSamples.count) * geometry.size.width
                                
                                EnhancedTransientMarkerView(
                                    transient: transient,
                                    position: transientX,
                                    height: geometry.size.height,
                                    velocityLayers: group.velocityLayers,
                                    isDragging: isDraggingTransient == transient.id,
                                    onDragStart: {
                                        isDraggingTransient = transient.id
                                    },
                                    onDragEnd: { newX in
                                        updateTransientPosition(transient: transient, newX: newX)
                                        isDraggingTransient = nil
                                    }
                                )
                            }
                        }
                    }
                }
                .onTapGesture {
                    if !isSelected {
                        groupManager.selectedGroupId = group.id
                    }
                }
            }
        }
    }
    
    private func updateGroupStart(delta: CGFloat) {
        let deltaFrames = Int64(delta / geometry.size.width * CGFloat(visibleSamples.count))
        let newStartFrame = max(0, group.startFrame + deltaFrames)
        
        if newStartFrame < group.endFrame - 1000 {
            var updatedGroup = group
            updatedGroup.startFrame = newStartFrame
            groupManager.updateGroup(updatedGroup)
        }
    }
    
    private func updateGroupEnd(delta: CGFloat) {
        let deltaFrames = Int64(delta / geometry.size.width * CGFloat(visibleSamples.count))
        let newEndFrame = min(totalFrames, group.endFrame + deltaFrames)
        
        if newEndFrame > group.startFrame + 1000 {
            var updatedGroup = group
            updatedGroup.endFrame = newEndFrame
            groupManager.updateGroup(updatedGroup)
        }
    }
    
    private func updateTransientPosition(transient: TransientMarker, newX: CGFloat) {
        let newFramePosition = visibleSamples.lowerBound + Int64(newX / geometry.size.width * CGFloat(visibleSamples.count))
        let clampedPosition = max(group.startFrame, min(group.endFrame, newFramePosition))
        
        if let groupIndex = groupManager.groups.firstIndex(where: { $0.id == group.id }),
           let transientIndex = groupManager.groups[groupIndex].transients.firstIndex(where: { $0.id == transient.id }) {
            
            var updatedTransient = transient
            updatedTransient.framePosition = clampedPosition
            groupManager.groups[groupIndex].transients[transientIndex] = updatedTransient
            
            // Re-sort transients
            groupManager.sortTransients(in: group.id)
        }
    }
}

struct SelectionHandle: View {
    let position: CGFloat
    let height: CGFloat
    @Binding var isDragging: Bool
    let onDrag: (CGFloat) -> Void
    
    @State private var dragStartX: CGFloat = 0
    
    var body: some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 8, height: height)
            .overlay(
                Rectangle()
                    .stroke(Color.black, lineWidth: 1)
            )
            .position(x: position, y: height / 2)
            .shadow(radius: 2)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartX = value.startLocation.x
                        }
                        let delta = value.location.x - dragStartX
                        onDrag(delta)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .cursor(.resizeLeftRight)
    }
}

struct EnhancedTransientMarkerView: View {
    let transient: TransientMarker
    let position: CGFloat
    let height: CGFloat
    let velocityLayers: Int
    let isDragging: Bool
    let onDragStart: () -> Void
    let onDragEnd: (CGFloat) -> Void
    
    private var markerColor: Color {
        let hue = CGFloat(transient.velocityLayer) / CGFloat(max(1, velocityLayers))
        return Color(hue: hue, saturation: 0.8, brightness: 0.9)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Marker line
            Rectangle()
                .fill(markerColor)
                .frame(width: isDragging ? 3 : 2, height: height * 0.8)
                .shadow(color: markerColor.opacity(0.5), radius: isDragging ? 4 : 2)
            
            // Velocity layer indicator
            if velocityLayers > 1 {
                Text("\(transient.velocityLayer + 1)")
                    .font(.system(size: 8))
                    .foregroundColor(.white)
                    .padding(.horizontal, 2)
                    .background(markerColor)
                    .cornerRadius(2)
                    .offset(y: -height * 0.4)
            }
        }
        .position(x: position, y: height / 2)
        .allowsHitTesting(true)
        .contentShape(Rectangle().size(width: 20, height: height))
        .gesture(
            DragGesture()
                .onChanged { value in
                    onDragStart()
                }
                .onEnded { value in
                    onDragEnd(value.location.x)
                }
        )
        .cursor(.pointingHand)
    }
}

// Cursor extension for better UX
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}