// AbletonSampler/AbletonSampler/WaveformDisplayView.swift
import SwiftUI

// MARK: - Segment Marker View (NEW)

/// A view for representing draggable start/end segment markers.
struct SegmentMarkerView: View {
    enum MarkerType {
        case start, end
    }

    let type: MarkerType
    @Binding var isBeingDragged: Bool

    private var color: Color {
        switch type {
        case .start: return .green
        case .end: return .red
        }
    }

    private var alignment: HorizontalAlignment {
         switch type {
         case .start: return .leading // Arrow points right
         case .end: return .trailing // Arrow points left
         }
     }

    private var arrowShape: Path {
         Path { path in
             let arrowWidth: CGFloat = 10
             let arrowHeight: CGFloat = 15
             let stemWidth: CGFloat = 2
             let totalHeight: CGFloat = 150 // Match waveform height

             // Position relative to the marker's center x
             let halfStem = stemWidth / 2

             if type == .start {
                 // Stem
                 path.move(to: CGPoint(x: -halfStem, y: 0))
                 path.addLine(to: CGPoint(x: -halfStem, y: totalHeight))
                 path.addLine(to: CGPoint(x: halfStem, y: totalHeight))
                 path.addLine(to: CGPoint(x: halfStem, y: arrowHeight))
                 // Arrowhead pointing right
                 path.addLine(to: CGPoint(x: arrowWidth, y: arrowHeight / 2))
                 path.addLine(to: CGPoint(x: halfStem, y: 0))
                 path.addLine(to: CGPoint(x: halfStem, y: arrowHeight)) // Close inner part
                 path.closeSubpath()

             } else { // End marker
                  // Stem
                 path.move(to: CGPoint(x: halfStem, y: 0))
                 path.addLine(to: CGPoint(x: halfStem, y: totalHeight))
                 path.addLine(to: CGPoint(x: -halfStem, y: totalHeight))
                 path.addLine(to: CGPoint(x: -halfStem, y: arrowHeight))
                  // Arrowhead pointing left
                 path.addLine(to: CGPoint(x: -arrowWidth, y: arrowHeight / 2))
                 path.addLine(to: CGPoint(x: -halfStem, y: 0))
                 path.addLine(to: CGPoint(x: -halfStem, y: arrowHeight)) // Close inner part
                 path.closeSubpath()
             }
         }
     }


    var body: some View {
        arrowShape
            .fill(color.opacity(isBeingDragged ? 0.9 : 0.7))
            .overlay(arrowShape.stroke(color, lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: isBeingDragged ? 4 : 2, x: 0, y: 1)
            .scaleEffect(isBeingDragged ? 1.1 : 1.0) // Make slightly larger when dragged
            .frame(width: 30, height: 150) // Ensure consistent frame for gesture
            .contentShape(Rectangle()) // Define tappable area
    }
}

// MARK: - Waveform Shape (UPDATED DRAWING - Removed Stride)

/// A Shape that draws a waveform based on RMS data, supporting horizontal/vertical zoom and scrolling.
struct WaveformShape: Shape {
    let rmsData: [Float]
    let verticalZoom: CGFloat
    let horizontalZoom: CGFloat
    let scrollOffset: CGFloat

    func path(in rect: CGRect) -> Path {
        guard !rmsData.isEmpty, rect.width > 0, rect.height > 0, horizontalZoom > 0 else {
            return Path()
        }

        let width = rect.width
        let height = rect.height
        let centerY = height / 2
        let totalWaveformWidth = width * horizontalZoom
        let pointWidth = totalWaveformWidth / CGFloat(max(1, rmsData.count))

        // --- Optimized Drawing with Vertical Bars (No Stride) --- 
        var path = Path()
        // Removed step calculation
        let barWidth: CGFloat = 1.0 // Draw 1-pixel wide bars for maximum detail

        let startIndexFloat = max(0, scrollOffset / pointWidth)
        let endIndexFloat = min(CGFloat(rmsData.count), (scrollOffset + width) / pointWidth)
        let startIndex = max(0, Int(startIndexFloat.rounded(.down)))
        let endIndex = min(rmsData.count, Int(endIndexFloat.rounded(.up)) + 1)

        guard startIndex < endIndex else { return path }

        // Iterate through ALL points in the visible range
        for index in startIndex..<endIndex {
            let rmsValue = rmsData[index]
            let xPositionInView = (CGFloat(index) * pointWidth) - scrollOffset
            let scaledAmplitude = CGFloat(rmsValue) * centerY * verticalZoom
            
            // Only add rect if it's potentially visible (minor optimization)
            guard xPositionInView + barWidth >= 0 && xPositionInView <= width else { continue }
            
            let barRect = CGRect(x: xPositionInView, 
                                 y: centerY - scaledAmplitude, 
                                 width: barWidth, // Use fixed 1px width
                                 height: scaledAmplitude * 2)
            path.addRect(barRect)
        }
        // ----------------------------------------------------
        return path
    }
}

// MARK: - Waveform View (UPDATED)

/// A View that displays the waveform using WaveformShape and handles basic interactions.
struct WaveformDisplayView: View {
    // Required Data
    let waveformRMSData: [Float]

    // Optional Segment Data
    let segmentStartSample: Int64?
    let segmentEndSample: Int64?
    let totalOriginalFrames: Int64?
    let onSegmentUpdate: ((_ newStartSample: Int64?, _ newEndSample: Int64?) -> Void)? // Callback

    // Zoom/Scroll State (Vertical Zoom is internal, Horizontal/Scroll are bindings)
    @State private var verticalZoom: CGFloat = 1.0
    @Binding var horizontalZoom: CGFloat
    @Binding var scrollOffsetPercentage: CGFloat

    // Scroll Drag Gesture State
    @GestureState private var waveformDragOffset: CGFloat = 0

    // Segment Marker Drag State
    @State private var draggingMarker: SegmentMarkerView.MarkerType? = nil
    @GestureState private var markerDragOffset: CGFloat = 0

    // Gesture state for scroll bar drag
    @GestureState private var scrollBarDragOffset: CGFloat = 0
    @State private var initialScrollPercentageOnDrag: CGFloat = 0 // Store initial value

    // Styling
    let backgroundColor: Color = Color.gray.opacity(0.4)
    let waveformColor: Color = Color.accentColor
    let scrollIndicatorColor: Color = Color.gray // Color for the scroll bar

    // MARK: Initialization (UPDATED)
    init(
        waveformRMSData: [Float],
        horizontalZoom: Binding<CGFloat>,            // Added Binding
        scrollOffsetPercentage: Binding<CGFloat>,  // Added Binding
        segmentStartSample: Int64? = nil,
        segmentEndSample: Int64? = nil,
        totalOriginalFrames: Int64? = nil,
        onSegmentUpdate: ((Int64?, Int64?) -> Void)? = nil
    ) {
        self.waveformRMSData = waveformRMSData
        self._horizontalZoom = horizontalZoom            // Assign Binding
        self._scrollOffsetPercentage = scrollOffsetPercentage // Assign Binding
        self.segmentStartSample = segmentStartSample
        self.segmentEndSample = segmentEndSample
        self.totalOriginalFrames = totalOriginalFrames
        self.onSegmentUpdate = onSegmentUpdate
    }

    // MARK: Computed Properties (UPDATED)

    var isLoading: Bool { waveformRMSData.isEmpty }
    var canDisplayMarkers: Bool {
        segmentStartSample != nil && segmentEndSample != nil && totalOriginalFrames != nil && totalOriginalFrames ?? 0 > 0
    }

    // MARK: Coordinate Conversion Helpers (UPDATED)
    // Need viewWidth passed in or calculated within body context
    private func calculateTotalWaveformWidth(viewWidth: CGFloat) -> CGFloat {
        viewWidth * horizontalZoom
    }
    private func calculateCurrentScrollOffsetPoints(viewWidth: CGFloat) -> CGFloat {
        let totalWidth = calculateTotalWaveformWidth(viewWidth: viewWidth)
        let excessW = max(0, totalWidth - viewWidth)
        return excessW * scrollOffsetPercentage
    }

    private func xPosition(for sample: Int64, viewWidth: CGFloat) -> CGFloat? {
        guard let totalFrames = totalOriginalFrames, totalFrames > 0 else { return nil }
        let totalWaveformW = calculateTotalWaveformWidth(viewWidth: viewWidth)
        let scrollOffsetPts = calculateCurrentScrollOffsetPoints(viewWidth: viewWidth)
        let normalizedPosition = CGFloat(sample) / CGFloat(totalFrames)
        let absoluteX = normalizedPosition * totalWaveformW
        let viewX = absoluteX - scrollOffsetPts
        return viewX
    }

    private func sample(for xPositionInView: CGFloat, viewWidth: CGFloat) -> Int64? {
        guard let totalFrames = totalOriginalFrames, totalFrames > 0 else { return nil }
        let totalWaveformW = calculateTotalWaveformWidth(viewWidth: viewWidth)
        guard totalWaveformW > 0 else { return nil } // Avoid division by zero
        let scrollOffsetPts = calculateCurrentScrollOffsetPoints(viewWidth: viewWidth)
        let absoluteX = xPositionInView + scrollOffsetPts
        let normalizedPosition = absoluteX / totalWaveformW
        let clampedNormalizedPosition = max(0.0, min(1.0, normalizedPosition))
        let sampleFrame = Int64(clampedNormalizedPosition * CGFloat(totalFrames))
        return sampleFrame
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 2) { 
                GeometryReader { geometry in
                    let currentViewWidth = geometry.size.width
                    let totalWaveformW = calculateTotalWaveformWidth(viewWidth: currentViewWidth)
                    let scrollOffsetPts = calculateCurrentScrollOffsetPoints(viewWidth: currentViewWidth)
                    let maxScrollOffsetPts = max(0, totalWaveformW - currentViewWidth)

                    ZStack {
                        backgroundColor
                        if isLoading { ProgressView() }
                        else {
                            WaveformShape(
                                rmsData: waveformRMSData,
                                verticalZoom: verticalZoom,
                                horizontalZoom: horizontalZoom,
                                scrollOffset: scrollOffsetPts
                            )
                            .fill(waveformColor)
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .updating($waveformDragOffset, body: { value, state, _ in
                                        if horizontalZoom > 1.0 && draggingMarker == nil {
                                            state = value.translation.width
                                        } else { state = 0 }
                                    })
                                    .onChanged { value in
                                        if horizontalZoom > 1.0 && draggingMarker == nil {
                                            // Calculate proposed offset based on *current* offset
                                            let proposedOffsetPoints = scrollOffsetPts - value.translation.width
                                            let clampedOffsetPoints = min(max(0, proposedOffsetPoints), maxScrollOffsetPts)
                                            // Update binding directly
                                            scrollOffsetPercentage = (maxScrollOffsetPts > 0) ? (clampedOffsetPoints / maxScrollOffsetPts) : 0
                                        }
                                    }
                                    .onEnded { value in // Use onChanged' logic, onEnded might be too late sometimes
                                         if horizontalZoom > 1.0 && draggingMarker == nil {
                                             let proposedOffsetPoints = scrollOffsetPts - value.translation.width
                                             let clampedOffsetPoints = min(max(0, proposedOffsetPoints), maxScrollOffsetPts)
                                             scrollOffsetPercentage = (maxScrollOffsetPts > 0) ? (clampedOffsetPoints / maxScrollOffsetPts) : 0
                                         }
                                     }
                            ) // End Waveform Scroll Gesture
                        }

                        // Layer 3: Segment Markers (UPDATED calculations)
                        if canDisplayMarkers, let startSample = segmentStartSample, let endSample = segmentEndSample, let totalFrames = totalOriginalFrames {
                            let startX = xPosition(for: startSample, viewWidth: currentViewWidth)
                            let endX = xPosition(for: endSample, viewWidth: currentViewWidth)
                            // Start Marker
                            if let startXPos = startX {
                                let isDraggingStart = draggingMarker == .start
                                let currentStartX = isDraggingStart ? startXPos + markerDragOffset : startXPos
                                SegmentMarkerView(type: .start, isBeingDragged: .constant(isDraggingStart))
                                    .position(x: currentStartX, y: geometry.size.height / 2)
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .updating($markerDragOffset) { value, state, _ in
                                                state = value.translation.width
                                                DispatchQueue.main.async { // Set dragging state on next cycle
                                                     if self.draggingMarker == nil { self.draggingMarker = .start }
                                                }
                                            }
                                            .onEnded { value in
                                                let finalX = startXPos + value.translation.width
                                                // Use geometry width for sample calculation
                                                if let newSample = sample(for: finalX, viewWidth: currentViewWidth) {
                                                     let validatedStart = max(0, min(newSample, endSample - 1))
                                                     print("Start Marker Drag End: Proposed=\(newSample), Validated=\(validatedStart)")
                                                     if validatedStart != startSample {
                                                          onSegmentUpdate?(validatedStart, nil)
                                                     }
                                                }
                                                draggingMarker = nil
                                            }
                                    ) // End Start Marker Gesture
                             }

                            // End Marker
                            if let endXPos = endX {
                                let isDraggingEnd = draggingMarker == .end
                                let currentEndX = isDraggingEnd ? endXPos + markerDragOffset : endXPos
                                SegmentMarkerView(type: .end, isBeingDragged: .constant(isDraggingEnd))
                                    .position(x: currentEndX, y: geometry.size.height / 2)
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .updating($markerDragOffset) { value, state, _ in
                                                state = value.translation.width
                                                DispatchQueue.main.async {
                                                     if self.draggingMarker == nil { self.draggingMarker = .end }
                                                }
                                            }
                                            .onEnded { value in
                                                let finalX = endXPos + value.translation.width
                                                // Use geometry width for sample calculation
                                                if let newSample = sample(for: finalX, viewWidth: currentViewWidth) {
                                                    let validatedEnd = min(totalFrames, max(startSample + 1, newSample))
                                                    print("End Marker Drag End: Proposed=\(newSample), Validated=\(validatedEnd)")
                                                    if validatedEnd != endSample {
                                                         onSegmentUpdate?(nil, validatedEnd)
                                                    }
                                                }
                                                draggingMarker = nil
                                            }
                                    ) // End End Marker Gesture
                            }

                        } // End if canDisplayMarkers

                    } // End ZStack
                    .frame(height: 150)
                    .clipped()
                    .contentShape(Rectangle())

                } // End GeometryReader
                .frame(height: 150) // Constrain GeometryReader height

                // --- Custom Scroll Indicator (UPDATED with DragGesture) --- 
                if horizontalZoom > 1.0 {
                    GeometryReader { geoIndicator in
                        let totalWidth = geoIndicator.size.width
                        let indicatorWidth = max(10, totalWidth / horizontalZoom)
                        let maxIndicatorX = totalWidth - indicatorWidth
                        let indicatorX = scrollOffsetPercentage * maxIndicatorX

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(scrollIndicatorColor.opacity(0.3))
                                .frame(height: 4)
                            Capsule()
                                .fill(scrollIndicatorColor)
                                .frame(width: indicatorWidth, height: 4)
                                .offset(x: indicatorX)
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .updating($scrollBarDragOffset) { value, state, _ in
                                            state = value.translation.width // Track drag distance
                                        }
                                        .onChanged { value in
                                            // Calculate new percentage based on drag from initial
                                            let dragDistance = value.translation.width
                                            let dragRatio = (maxIndicatorX > 0) ? dragDistance / maxIndicatorX : 0
                                            scrollOffsetPercentage = max(0.0, min(1.0, initialScrollPercentageOnDrag + dragRatio))
                                        }
                                        .onEnded { value in 
                                            // Final update on end (optional, onChanged often suffices)
                                            let dragDistance = value.translation.width
                                            let dragRatio = (maxIndicatorX > 0) ? dragDistance / maxIndicatorX : 0
                                            scrollOffsetPercentage = max(0.0, min(1.0, initialScrollPercentageOnDrag + dragRatio))
                                        }
                                )
                                // Store initial scroll % when drag begins on the thumb
                                .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in 
                                     // This seems hacky, but captures the start of any drag on the thumb
                                     // Need a better way? Maybe just capture in .updating?
                                     // Let's try capturing in .updating for simplicity
                                     // self.initialScrollPercentageOnDrag = scrollOffsetPercentage // Capture initial value
                                     // UPDATE: Let's try using the gesture state itself
                                      if scrollBarDragOffset == 0 { // Approximates start of drag
                                           self.initialScrollPercentageOnDrag = scrollOffsetPercentage
                                       }
                                })
                        }
                        .frame(height: geoIndicator.size.height) // Fill indicator frame height
                    }
                    .frame(height: 8) // Increased height for easier grabbing
                    .padding(.horizontal, 5)
                    .opacity(horizontalZoom > 1.0 ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.1), value: horizontalZoom > 1.0)
                } else {
                    Spacer().frame(height: 8) // Match height
                }
            } // End VStack for Waveform+Scroll

            // --- Vertical Slider Area (UPDATED with Rotation) --- 
            VStack(spacing: 4) { 
                Slider(value: $verticalZoom, in: 0.1...10.0)
                    .rotationEffect(.degrees(-90)) // Rotate the slider
                    .frame(width: 100) // Control the slider's extent *before* rotation
                
                Text(String(format: "%.1fx", verticalZoom))
                    .font(.caption2)
                    // Optionally rotate text too, or keep horizontal?
                    // .rotationEffect(.degrees(-90))
            }
            .frame(width: 30) // Control the width allocated to the Vstack
            .padding(.vertical, 15) // Add padding to visually center rotated slider
            // --- END Vertical Slider Area ---
        } // End Main HStack
    } // End body
}

// MARK: - Preview (Adjusted)
struct WaveformDisplayView_Previews: PreviewProvider {
    // Generate sample data
    static let sampleRMSData: [Float] = {
        let frequency: Float = 5.0; let amplitude: Float = 0.8; let length = 1000
        return (0..<length).map { i in max(0, abs(amplitude * sin(2.0 * .pi * frequency * Float(i) / Float(length)) * (Float(length - i) / Float(length))) + Float.random(in: -0.1...0.1)) }
    }()
    // Dummy segment data for preview
    static let totalFrames: Int64 = 44100 * 2 // 2 seconds
    @State static var startSample: Int64 = totalFrames / 4 // 0.5s
    @State static var endSample: Int64 = totalFrames * 3 / 4 // 1.5s
    // Add State vars for bindings in preview
    @State static var hZoom: CGFloat = 1.5
    @State static var scrollPct: CGFloat = 0.2

    static var previews: some View {
        VStack {
            Text("With Segment Markers")
                .foregroundColor(.white)
            WaveformDisplayView(
                 waveformRMSData: sampleRMSData,
                 horizontalZoom: $hZoom,
                 scrollOffsetPercentage: $scrollPct,
                 segmentStartSample: startSample,
                 segmentEndSample: endSample,
                 totalOriginalFrames: totalFrames,
                 onSegmentUpdate: { newStart, newEnd in
                     print("Preview Update: Start=\(String(describing: newStart)), End=\(String(describing: newEnd))")
                     if let ns = newStart { startSample = ns }
                     if let ne = newEnd { endSample = ne }
                 }
            )
            HStack {
                Text("HZoom:")
                Slider(value: $hZoom, in: 1.0...10.0)
            }
             HStack {
                Text("Scroll:")
                Slider(value: $scrollPct, in: 0.0...1.0)
            }
            Divider()
            Text("Without Segment Markers")
                .foregroundColor(.white)
            WaveformDisplayView(
                waveformRMSData: sampleRMSData,
                horizontalZoom: .constant(1.0),
                scrollOffsetPercentage: .constant(0.0)
            )
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .previewLayout(.sizeThatFits)
        .frame(width: 450) // Wider preview to accommodate slider
    }
} 