import SwiftUI

/// Overlay view that displays transient groups on top of a waveform
struct GroupOverlayView: View {
    @ObservedObject var groupManager: TransientGroupManager
    let totalFrames: Int64
    let geometry: GeometryProxy
    let timeZoomScale: CGFloat
    let scrollOffset: CGPoint
    
    init(groupManager: TransientGroupManager, totalFrames: Int64, geometry: GeometryProxy, timeZoomScale: CGFloat, scrollOffset: CGPoint) {
        self.groupManager = groupManager
        self.totalFrames = totalFrames
        self.geometry = geometry
        self.timeZoomScale = timeZoomScale
        self.scrollOffset = scrollOffset
        print("[GroupOverlay] Init with totalFrames=\(totalFrames), viewWidth=\(String(format: "%.1f", geometry.size.width)), zoom=\(String(format: "%.2f", timeZoomScale)), scroll=\(String(format: "%.1f", scrollOffset.x))")
    }
    
    // Interaction
    @State private var isDraggingGroup = false
    @State private var draggedGroupId: UUID?
    @State private var isDraggingTransient = false
    @State private var draggedTransientId: UUID?
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Draw each group
            ForEach(groupManager.groups) { group in
                GroupRegionView(
                    group: group,
                    totalFrames: totalFrames,
                    geometry: geometry,
                    timeZoomScale: timeZoomScale,
                    scrollOffset: scrollOffset,
                    isSelected: groupManager.selectedGroupId == group.id,
                    onSelect: {
                        groupManager.selectedGroupId = group.id
                    },
                    onUpdate: { updatedGroup in
                        groupManager.updateGroup(updatedGroup)
                    }
                )
            }
            
            // Draw transient markers for selected group
            if let selectedGroup = groupManager.groups.first(where: { $0.id == groupManager.selectedGroupId }) {
                ForEach(selectedGroup.transients) { transient in
                    TransientMarkerView(
                        transient: transient,
                        group: selectedGroup,
                        totalFrames: totalFrames,
                        geometry: geometry,
                        timeZoomScale: timeZoomScale,
                        scrollOffset: scrollOffset,
                        onUpdate: { framePosition in
                            updateTransientPosition(
                                groupId: selectedGroup.id,
                                transientId: transient.id,
                                newPosition: framePosition
                            )
                        }
                    )
                }
            }
        }
    }
    
    private func updateTransientPosition(groupId: UUID, transientId: UUID, newPosition: Int64) {
        guard let groupIndex = groupManager.groups.firstIndex(where: { $0.id == groupId }),
              let transientIndex = groupManager.groups[groupIndex].transients.firstIndex(where: { $0.id == transientId }) else {
            return
        }
        
        var transient = groupManager.groups[groupIndex].transients[transientIndex]
        transient.framePosition = newPosition
        groupManager.groups[groupIndex].transients[transientIndex] = transient
    }
}

/// View for a single group region
struct GroupRegionView: View {
    let group: TransientGroup
    let totalFrames: Int64
    let geometry: GeometryProxy
    let timeZoomScale: CGFloat
    let scrollOffset: CGPoint
    let isSelected: Bool
    let onSelect: () -> Void
    let onUpdate: (TransientGroup) -> Void
    
    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    @State private var isResizingStart = false
    @State private var isResizingEnd = false
    @State private var initialStartFrame: Int64 = 0
    @State private var initialEndFrame: Int64 = 0
    
    private var xPosition: CGFloat {
        let progress = CGFloat(group.startFrame) / CGFloat(totalFrames)
        let position = (geometry.size.width * timeZoomScale * progress) - scrollOffset.x
        return position
    }
    
    private var width: CGFloat {
        let startProgress = CGFloat(group.startFrame) / CGFloat(totalFrames)
        let endProgress = CGFloat(group.endFrame) / CGFloat(totalFrames)
        let width = geometry.size.width * timeZoomScale * (endProgress - startProgress)
        return width
    }
    
    private var color: Color {
        Color(hex: group.color) ?? .blue
    }
    
    var body: some View {
        // Check if the group is at least partially visible
        // Scale the visibility buffer based on zoom level to handle high zoom scenarios
        let visibilityBuffer = max(1000, geometry.size.width * timeZoomScale)
        let isVisible = (xPosition + width) > -visibilityBuffer && xPosition < (geometry.size.width + visibilityBuffer)
        
        // Debug logging
        let _ = print("[GroupRegion] \(group.name): frames=\(group.startFrame)-\(group.endFrame), xPos=\(String(format: "%.1f", xPosition)), width=\(String(format: "%.1f", width)), visible=\(isVisible), zoom=\(String(format: "%.1f", timeZoomScale)), scroll=\(String(format: "%.1f", scrollOffset.x))")
        
        Group {
            if isVisible {
                ZStack(alignment: .leading) {
                    // Main region
                    Rectangle()
                        .fill(color.opacity(isSelected ? 0.3 : 0.2))
                        .overlay(
                            Rectangle()
                                .stroke(color, lineWidth: isSelected ? 2 : 1)
                        )
                        .frame(width: width, height: geometry.size.height)
                        .position(x: xPosition + width/2, y: geometry.size.height/2)
                        .onTapGesture {
                            print("[GroupSelect] Selected group '\(group.name)' frames=\(group.startFrame)-\(group.endFrame)")
                            onSelect()
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if !isResizingStart && !isResizingEnd {
                                        if !isDragging {
                                            isDragging = true
                                            initialStartFrame = group.startFrame
                                            initialEndFrame = group.endFrame
                                        }
                                        // Update position continuously during drag
                                        applyDrag(offset: value.translation.width)
                                    }
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    dragOffset = 0
                                }
                        )
                    
                    // Resize handles
                    if isSelected {
                        // Start handle
                        Rectangle()
                            .fill(color)
                            .frame(width: 8, height: geometry.size.height)
                            .position(x: xPosition, y: geometry.size.height/2)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if !isResizingStart {
                                            isResizingStart = true
                                            initialStartFrame = group.startFrame
                                            initialEndFrame = group.endFrame
                                        }
                                        resizeStart(offset: value.translation.width)
                                    }
                                    .onEnded { _ in
                                        isResizingStart = false
                                    }
                            )
                        
                        // End handle
                        Rectangle()
                            .fill(color)
                            .frame(width: 8, height: geometry.size.height)
                            .position(x: xPosition + width, y: geometry.size.height/2)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if !isResizingEnd {
                                            isResizingEnd = true
                                            initialStartFrame = group.startFrame
                                            initialEndFrame = group.endFrame
                                        }
                                        resizeEnd(offset: value.translation.width)
                                    }
                                    .onEnded { _ in
                                        isResizingEnd = false
                                    }
                            )
                    }
            
                    // Label
                    if isSelected {
                        Text(group.name)
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(color)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .position(x: xPosition + width/2, y: 20)
                    }
                }
            }
        }
    }
    
    private func applyDrag(offset: CGFloat) {
        // The offset is in screen coordinates, need to convert to frame coordinates
        let totalZoomedWidth = geometry.size.width * timeZoomScale
        let frameOffset = Int64((offset / totalZoomedWidth) * CGFloat(totalFrames))
        var updatedGroup = group
        // Use initial positions to calculate new positions
        updatedGroup.startFrame = max(0, initialStartFrame + frameOffset)
        updatedGroup.endFrame = min(totalFrames, initialEndFrame + frameOffset)
        onUpdate(updatedGroup)
    }
    
    private func resizeStart(offset: CGFloat) {
        // The offset is in screen coordinates, need to convert to frame coordinates
        // Divide by the total zoomed width to get the fraction of the audio file
        let totalZoomedWidth = geometry.size.width * timeZoomScale
        let frameOffset = Int64((offset / totalZoomedWidth) * CGFloat(totalFrames))
        var updatedGroup = group
        // Use initialStartFrame as the base, not the current position
        updatedGroup.startFrame = max(0, min(initialEndFrame - 1000, initialStartFrame + frameOffset))
        updatedGroup.endFrame = initialEndFrame // Keep end frame at initial position
        onUpdate(updatedGroup)
    }
    
    private func resizeEnd(offset: CGFloat) {
        // The offset is in screen coordinates, need to convert to frame coordinates
        // Divide by the total zoomed width to get the fraction of the audio file
        let totalZoomedWidth = geometry.size.width * timeZoomScale
        let frameOffset = Int64((offset / totalZoomedWidth) * CGFloat(totalFrames))
        var updatedGroup = group
        updatedGroup.startFrame = initialStartFrame // Keep start frame at initial position
        // Use initialEndFrame as the base, not the current position
        updatedGroup.endFrame = min(totalFrames, max(initialStartFrame + 1000, initialEndFrame + frameOffset))
        onUpdate(updatedGroup)
    }
}

/// View for a single transient marker
struct TransientMarkerView: View {
    let transient: TransientMarker
    let group: TransientGroup
    let totalFrames: Int64
    let geometry: GeometryProxy
    let timeZoomScale: CGFloat
    let scrollOffset: CGPoint
    let onUpdate: (Int64) -> Void
    
    @State private var isDragging = false
    @State private var initialFramePosition: Int64 = 0
    
    private var xPosition: CGFloat {
        let progress = CGFloat(transient.framePosition) / CGFloat(totalFrames)
        return (geometry.size.width * timeZoomScale * progress) - scrollOffset.x
    }
    
    private var color: Color {
        // Color based on velocity layer
        let hue = Double(transient.velocityLayer) / Double(max(1, group.velocityLayers))
        return Color(hue: hue, saturation: 0.8, brightness: 0.9)
    }
    
    var body: some View {
        // Check if the marker is visible - use same buffer calculation as groups
        let visibilityBuffer = max(1000, geometry.size.width * timeZoomScale)
        let isVisible = xPosition > -visibilityBuffer && xPosition < (geometry.size.width + visibilityBuffer)
        
        Group {
            if isVisible {
                VStack(spacing: 2) {
                    // Marker line
                    Rectangle()
                        .fill(color)
                        .frame(width: 2, height: geometry.size.height * 0.8)
                    
                    // Label
                    Text("V\(transient.velocityLayer + 1) R\(transient.roundRobinIndex + 1)")
                        .font(.system(size: 9))
                        .padding(.horizontal, 2)
                        .background(color)
                        .foregroundColor(.white)
                        .cornerRadius(2)
                }
                .position(x: xPosition, y: geometry.size.height/2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                initialFramePosition = transient.framePosition
                            }
                            
                            // Calculate new position based on initial position + drag offset
                            let totalZoomedWidth = geometry.size.width * timeZoomScale
                            let frameOffset = Int64((value.translation.width / totalZoomedWidth) * CGFloat(totalFrames))
                            let newFrame = initialFramePosition + frameOffset
                            
                            // Constrain to group bounds
                            let constrainedFrame = min(max(group.startFrame, newFrame), group.endFrame)
                            onUpdate(constrainedFrame)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
        }
    }
}

// Helper extension for hex color support
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}