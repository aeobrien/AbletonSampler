import SwiftUI
import AVFoundation
import AudioKit
import Waveform

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
    let targetNoteOverride: Int? // If provided, restricts mapping options
    
    // --- State for Audio Data & Waveform ---
    @State private var audioFile: AVAudioFile? = nil
    @State private var audioInfo: String = "Loading audio..."
    @State private var totalFrames: Int64? = nil
    
    // --- State for waveform RMS data (kept for transient detection) ---
    @State private var waveformRMSData: [Float] = []
    @State private var rawAudioData: [Float] = []
    @State private var isLoadingWaveform = true
    @State private var sampleBuffer: SampleBuffer?
    @State private var peakAmplitude: Float = 1.0

    // --- State for Markers & Segments ---
    @State private var markers: [Double] = [] // Sorted normalized positions (0.0-1.0)
    @State private var selectedSegmentIndex: Int? = nil
    
    // --- State for Mapping ---
    @State private var targetMidiNote: Int = 60
    
    // --- State for transient tracking ---
    @State private var originalTransientIndices: [Int] = []
    @State private var markerOriginalIndexMap: [Int: Double] = [:]
    
    // --- NEW: State for Waveform Zoom and Pan ---
    @State private var amplitudeScale: CGFloat = 1.0 // Vertical scaling
    @State private var visibleSamples: Range<Int64> = 0..<1
    @GestureState private var dragOffset: CGFloat = 0
    @State private var dragStartVisibleSamples: Range<Int64> = 0..<1

    // --- NEW: State for selecting the target layer for RR mapping ---
    @State private var selectedLayerIndex: Int = 0
    
    // --- NEW: State for Groups Mode ---
    @State private var isGroupsMode: Bool = false
    @StateObject private var groupManager = TransientGroupManager()
    @State private var isDraggingToCreateGroup = false
    @State private var groupDragStart: CGFloat = 0
    @State private var groupDragEnd: CGFloat = 0
    
    // --- Computed property for the full MIDI range (0-127) ---
    private var availablePianoKeys: [PianoKey] {
        return viewModel.pianoKeys
    }
    
    // --- NEW: State for Dragging Markers ---
    @State private var draggedMarkerIndex: Int? = nil
    
    // --- NEW: Auto-Mapping State (Updated Defaults) ---
    @State private var autoMapStartNote: Int = 24
    @State private var velocityMapTargetNote: Int = 60
    @State private var roundRobinTargetNote: Int = 60
    
    // --- NEW: Transient Detection State ---
    @State private var transientThreshold: Double = 0.1
    @State private var transientPreemptSamples: Int = 1
    
    // --- Computed Property: Number of Segments ---
    private var numberOfSegments: Int {
        markers.count + 1
    }
   
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Audio Segment Editor")
                .font(.title2)

            Text("Editing: \(audioFileURL.lastPathComponent)")
                .font(.caption)
                .lineLimit(1)
            
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isGroupsMode.toggle()
                        if isGroupsMode {
                            groupManager.audioFileURL = audioFileURL
                            groupManager.totalFrames = totalFrames ?? 0
                            groupManager.sampleRate = audioFile?.processingFormat.sampleRate ?? 44100
                        }
                    }
                }) {
                    Label(isGroupsMode ? "Exit Groups" : "Groups Assignment",
                          systemImage: isGroupsMode ? "xmark.circle" : "rectangle.3.group")
                }
                .buttonStyle(.bordered)
                .tint(isGroupsMode ? .red : .accentColor)
                Spacer()
            }
            .padding(.horizontal)

           
            
            // --- Waveform + optional Groups panel ---
            if isGroupsMode {
                HStack(spacing: 8) {
                    waveformDisplayArea

                    GroupManagementPanel(groupManager: groupManager)
                        .environmentObject(viewModel)
                        .frame(width: 300)
                }
                .frame(height: 170)
            } else {
                HStack(alignment: .center, spacing: 5) {
                    waveformDisplayArea
                    amplitudeSlider
                }
            }

            // --- Mode-specific Controls ---
            if !isGroupsMode {
                standardModeControls
            } else {
                GroupsAssignmentView(
                    groupManager: groupManager,
                    selectedGroupId: $groupManager.selectedGroupId,
                    audioFile: audioFile,
                    waveformRMSData: waveformRMSData,
                    rawAudioData: rawAudioData,
                    totalFrames: totalFrames
                )
                .environmentObject(viewModel)
                .frame(height: 200)
            }

            if !isGroupsMode {
                Text(audioInfo).font(.footnote)
                Text("Segments Defined: \(numberOfSegments)").font(.footnote)
            }

            // --- CONDITIONAL MAPPING CONTROLS ---
            if !isGroupsMode && targetNoteOverride == nil {
                autoMappingControls
            } else if !isGroupsMode {
                restrictedMappingControls
            }
            
            actionButtons
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 650)
        .task {
            await loadAudioAndWaveform()
        }
        .onChange(of: transientPreemptSamples) { _, newValue in
            guard !markerOriginalIndexMap.isEmpty else { return }
            updateMappedMarkerPositions(preempt: newValue)
        }
        .onChange(of: transientThreshold) { _, _ in
            guard !isLoadingWaveform else { return }
            detectAndSetTransients()
        }
        .onChange(of: targetMidiNote) { _, _ in
             if targetNoteOverride == nil {
                 selectedLayerIndex = 0
             }
        }
    }
    
    // MARK: - Subviews
    
    private func calculateWaveformParams(buffer: SampleBuffer, geometry: GeometryProxy) -> (start: Int, length: Int) {
        let totalFrames = totalFrames ?? 1
        
        let visibleStart = Int(
            Double(buffer.count) *
            Double(visibleSamples.lowerBound) /
            Double(totalFrames)
        )
        
        let visibleLength = Int(
            Double(buffer.count) *
            Double(visibleSamples.count) /
            Double(totalFrames)
        )
        
        return (max(0, visibleStart), max(1, visibleLength))
    }
    
    @ViewBuilder
    private func waveformView(buffer: SampleBuffer, geometry: GeometryProxy) -> some View {
        let params = calculateWaveformParams(buffer: buffer, geometry: geometry)
        let scaleY = amplitudeScale * CGFloat(1 / peakAmplitude)
        
        Waveform(
            samples: buffer,
            start: params.start,
            length: params.length
        )
        .foregroundColor(.accentColor)
        .scaleEffect(y: scaleY)
        .allowsHitTesting(!isGroupsMode)
        .gesture(
            isGroupsMode ? nil : DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if value.translation.width == 0 {
                        dragStartVisibleSamples = visibleSamples
                    }
                    panWaveform(value)
                }
        )
    }
    
    @ViewBuilder
    private func groupGestureOverlay(geometry: GeometryProxy) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if !isDraggingToCreateGroup {
                            isDraggingToCreateGroup = true
                            groupDragStart = value.startLocation.x
                        }
                        groupDragEnd = value.location.x
                    }
                    .onEnded { value in
                        if isDraggingToCreateGroup, let totalFrames = totalFrames {
                            let startFraction = (groupDragStart / geometry.size.width) * (Double(visibleSamples.count) / Double(totalFrames)) + (Double(visibleSamples.lowerBound) / Double(totalFrames))
                            let endFraction = (groupDragEnd / geometry.size.width) * (Double(visibleSamples.count) / Double(totalFrames)) + (Double(visibleSamples.lowerBound) / Double(totalFrames))
                            
                            let startFrame = Int64(startFraction * CGFloat(totalFrames))
                            let endFrame = Int64(endFraction * CGFloat(totalFrames))
                            
                            if abs(endFrame - startFrame) > 1000 {
                                let group = groupManager.createGroup(startFrame: min(startFrame, endFrame), endFrame: max(startFrame, endFrame))
                                print("[GroupCreate] Created group '\(group.name)'")
                            }
                        }
                        isDraggingToCreateGroup = false
                    }
            )
    }
    
    @ViewBuilder
    private var waveformDisplayArea: some View {
        VStack {
            if isLoadingWaveform {
                ProgressView()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            } else if audioFile != nil {
                GeometryReader { geometry in
                    ZStack {
                        // Layer 1: Waveform
                        if let buffer = sampleBuffer {
                            waveformView(buffer: buffer, geometry: geometry)
                        }
                        
                        // Layer 2: Marker and Group Overlay
                        markerAndGroupOverlay(geometry: geometry)
                        
                        // Layer 3: Gesture overlay for groups mode
                        if isGroupsMode {
                            groupGestureOverlay(geometry: geometry)
                                .onTapGesture(count: 2) { location in
                                    handleDoubleClick(at: location, geometry: geometry)
                                }
                        } else {
                            // Double-click support for standard mode
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { location in
                                    handleDoubleClick(at: location, geometry: geometry)
                                }
                        }
                    }
                }
                .frame(height: 150)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(Text("Could not load waveform").foregroundColor(.white))
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            }

            // --- Horizontal Time Zoom Slider ---
            zoomSlider
            scrollSlider
        }
    }

    @ViewBuilder
    private var zoomSlider: some View {
        let maxZoom = Double(totalFrames ?? 1) / 100000.0 // Allow zooming until 1000 samples are visible
        HStack {
            Text("Zoom:")
            Slider(
                value: .init(
                    get: { Double(totalFrames ?? 1) / Double(visibleSamples.count) },
                    set: { zoomLevel in
                        zoomWaveform(to: zoomLevel)
                    }
                ),
                in: 1.0...max(1.0, maxZoom)
            )
            Text(String(format: "%.1fx", Double(totalFrames ?? 1) / Double(visibleSamples.count)))
        }
        .padding(.top, 5)
        .disabled(isLoadingWaveform || audioFile == nil)
    }
    
    // --- NEW: Horizontal scroll slider ---
    // --- Horizontal scroll slider (always visible) ---
    @ViewBuilder
    private var scrollSlider: some View {
        let total = totalFrames ?? 0
        let span  = visibleSamples.count

        // binding extracted so the compiler stays fast
        let scrollBinding = Binding<Double>(
            get: {
                guard total > 0, span < total else { return 0 }
                return Double(visibleSamples.lowerBound) /
                       Double(total - Int64(span))
            },
            set: { v in
                guard total > 0 else { return }
                let newStart = Int64(v * Double(total - Int64(span)))
                visibleSamples = newStart ..< (newStart + Int64(span))
            })

        HStack {
            Text("Scroll:")
            Slider(value: scrollBinding, in: 0...1)
                .disabled(total == 0 || span >= total)   // greyed-out when there’s nothing to scroll
        }
        .padding(.top, 2)
    }



    @ViewBuilder
    private var amplitudeSlider: some View {
        Slider(value: $amplitudeScale, in: 0.1...5.0)
            .frame(width: 130, height: 20)
            .rotationEffect(.degrees(-90))
            .frame(width: 20, height: 150)
            .padding(.leading, 5)
            .disabled(isLoadingWaveform || audioFile == nil)
    }
    
    
    @ViewBuilder
    private func markerAndGroupOverlay(geometry: GeometryProxy) -> some View {
        // Overlay for placing markers and handling group creation drags
        ZStack(alignment: .leading) {
            // Logic for groups mode selection and dragging
            if isGroupsMode {
                if isDraggingToCreateGroup {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: abs(groupDragEnd - groupDragStart), height: geometry.size.height)
                        .offset(x: min(groupDragStart, groupDragEnd))
                }
                
                ForEach(groupManager.groups) { group in
                    EnhancedGroupOverlayView(
                        group: group,
                        geometry: geometry,
                        visibleSamples: visibleSamples,
                        totalFrames: totalFrames ?? 0,
                        isSelected: groupManager.selectedGroupId == group.id,
                        groupManager: groupManager
                    )
                }
            }
            
            // Logic for drawing individual markers
            if !isGroupsMode {
                ForEach(markers.indices, id: \.self) { index in
                    let isDragged = (draggedMarkerIndex == index)
                    let markerPos = markers[index]
                    
                    // Calculate position within the visible rect
                    if let file = audioFile {
                        let totalFileSamples = file.length
                        let markerSample = Int64(markerPos * Double(totalFileSamples))
                        
                        if visibleSamples.contains(markerSample) {
                            let relativePos = Double(markerSample - visibleSamples.lowerBound) / Double(visibleSamples.count)
                            let xPos = relativePos * geometry.size.width
                            
                             MarkerView(isBeingDragged: .constant(isDragged), viewHeight: geometry.size.height)
                                .position(x: xPos, y: geometry.size.height / 2)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            draggedMarkerIndex = index
                                            let newX = value.location.x
                                            let normalizedX = newX / geometry.size.width
                                            
                                            let newSamplePosition = visibleSamples.lowerBound + Int64(normalizedX * Double(visibleSamples.count))
                                            let newNormalizedPos = Double(newSamplePosition) / Double(totalFileSamples)
                                            
                                            markers[index] = max(0.0, min(1.0, newNormalizedPos))
                                        }
                                        .onEnded { _ in
                                            markers.sort()
                                            draggedMarkerIndex = nil
                                        }
                                )
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle()) // Makes the whole area tappable
    }
    
    @ViewBuilder
    private func groupView(group: TransientGroup, geometry: GeometryProxy) -> some View {
        if let totalFrames = totalFrames, totalFrames > 0 {
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

                let color = Color(group.color) ?? .blue
                let isSelected = (groupManager.selectedGroupId == group.id)

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(color.opacity(isSelected ? 0.3 : 0.2))
                    
                    Rectangle()
                        .stroke(color, lineWidth: isSelected ? 2 : 1)
                    
                    if isSelected {
                        // Draw transients within the group
                        ForEach(group.transients, id: \.framePosition) { transient in
                            let transientSample = transient.framePosition
                            if visibleSamples.contains(transientSample) {
                                let transientX = CGFloat(transientSample - visibleSamples.lowerBound) / CGFloat(visibleSamples.count) * geometry.size.width
                                let hue = CGFloat(transient.velocityLayer) / CGFloat(max(1, group.velocityLayers))
                                let transientColor = Color(hue: hue, saturation: 0.8, brightness: 0.9)
                                
                                Rectangle()
                                    .fill(transientColor)
                                    .frame(width: 2, height: geometry.size.height * 0.8)
                                    .position(x: transientX, y: geometry.size.height / 2)
                            }
                        }
                    }
                }
                .frame(width: rectWidth, height: geometry.size.height)
                .offset(x: startX)
                .onTapGesture {
                    groupManager.selectedGroupId = group.id
                }
            }
        }
    }

    @ViewBuilder
    private var standardModeControls: some View {
        HStack {
            Button("Clear All Markers") {
                markers.removeAll()
                originalTransientIndices = []
                markerOriginalIndexMap = [:]
                selectedSegmentIndex = nil
            }
            .disabled(markers.isEmpty)

            VStack(alignment: .trailing, spacing: 5) {
                HStack {
                    Text("Sensitivity:")
                    Slider(value: $transientThreshold, in: 0.01...1.0).frame(width: 100)
                }.font(.caption)

                HStack {
                    Text("Pre-detect Samples:")
                    Stepper("\(transientPreemptSamples)", value: $transientPreemptSamples, in: 0...20)
                }.font(.caption)

                Button("Detect Transients") {
                    detectAndSetTransients()
                }
                .disabled(isLoadingWaveform || waveformRMSData.isEmpty)
            }
        }.padding(.horizontal)
    }

    @ViewBuilder
    private var groupsModeControls: some View {
        if let selectedGroup = groupManager.groups.first(where: { $0.id == groupManager.selectedGroupId }) {
            VStack(spacing: 10) {
                GroupDetailView(
                    group: selectedGroup,
                    groupManager: groupManager,
                    audioFile: audioFile,
                    waveformRMSData: waveformRMSData,
                    rawAudioData: rawAudioData,
                    totalFrames: totalFrames
                )
                Button("Zoom to Group") {
                    zoomToGroup(selectedGroup)
                }.buttonStyle(.bordered)
            }
            .padding(.horizontal)
        } else {
            Text("Click and drag on the waveform to create a group").font(.caption).foregroundColor(.secondary).padding()
        }
    }
    
    @ViewBuilder
    private var autoMappingControls: some View {
        VStack {
            Text("Auto-Mapping (All Segments)").font(.headline)
            HStack {
                Text("Map Sequentially starting at note:")
                Picker("Start Note", selection: $autoMapStartNote) {
                    ForEach(availablePianoKeys) { key in Text("\(key.name) (\(key.id))").tag(key.id) }
                }.frame(width: 120).labelsHidden()
                Spacer()
                Button("Map Sequentially") { autoMapAllSegmentsSequentially(vm: self.viewModel) }
                    .buttonStyle(.bordered).disabled(markers.isEmpty && numberOfSegments <= 1)
            }
            HStack {
                Text("Map to Velocity Zones on note:")
                Picker("Target Note", selection: $targetMidiNote) {
                    ForEach(availablePianoKeys) { key in Text("\(key.name) (\(key.id))").tag(key.id) }
                }.frame(width: 120).labelsHidden()
                Spacer()
                Button("Map Velocity Zones") { mapAllSegmentsAsVelocityZones(targetNote: targetMidiNote, vm: self.viewModel) }
                    .buttonStyle(.bordered).disabled(markers.isEmpty && numberOfSegments <= 1)
            }
            HStack {
                Text("Map as Round Robin on note:")
                Picker("Target Note", selection: $targetMidiNote) {
                    ForEach(availablePianoKeys) { key in Text("\(key.name) (\(key.id))").tag(key.id) }
                }.frame(maxWidth: 120).labelsHidden()
                let layerCount = viewModel.noteLayerConfiguration[targetMidiNote] ?? 1
                Picker("Target Layer", selection: $selectedLayerIndex) {
                    ForEach(0..<layerCount) { index in Text("Layer \(index + 1)").tag(index) }
                }.frame(maxWidth: 120).clipped().disabled(layerCount <= 1)
                Spacer()
                Button("Map Round Robin") {
                    mapAllSegmentsAsRoundRobin(targetNote: targetMidiNote, targetLayer: selectedLayerIndex, vm: self.viewModel)
                }.buttonStyle(.bordered).disabled(markers.isEmpty && numberOfSegments <= 1)
            }
        }
    }

    @ViewBuilder
    private var restrictedMappingControls: some View {
        let fixedTargetNote = targetNoteOverride!
        VStack {
            Text("Map Segments to Note \(fixedTargetNote)").font(.headline)
            HStack {
                Button("Map Segments as Velocity Zones") {
                    mapAllSegmentsAsVelocityZones(targetNote: fixedTargetNote, vm: self.viewModel)
                }.buttonStyle(.bordered).disabled(markers.isEmpty && numberOfSegments <= 1)
                Spacer()
            }.frame(maxWidth: .infinity)
            HStack {
                let layerCount = viewModel.noteLayerConfiguration[fixedTargetNote] ?? 1
                Picker("Target Layer", selection: $selectedLayerIndex) {
                    ForEach(0..<layerCount) { index in Text("Layer \(index + 1)").tag(index) }
                }.frame(maxWidth: 120).clipped().disabled(layerCount <= 1)
                Spacer()
                Button("Map Segments as Round Robin") {
                    mapAllSegmentsAsRoundRobin(targetNote: fixedTargetNote, targetLayer: selectedLayerIndex, vm: self.viewModel)
                }.buttonStyle(.bordered).disabled(markers.isEmpty && numberOfSegments <= 1)
            }.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
            Spacer()
            if isGroupsMode && !groupManager.groups.isEmpty {
                Button("Export Groups") { exportGroups() }.buttonStyle(.bordered)
            }
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Helper Functions
    
    // MARK: - Faster zoom / pan (replace both old functions)
    private func zoomWaveform(to zoomLevel: Double) {
        guard let total = totalFrames, total > 0 else { return }
        let newCount = Int64(Double(total) / zoomLevel)
        let centre   = visibleSamples.lowerBound + Int64(visibleSamples.count / 2)
        var start    = max(0, centre - newCount / 2)
        if start + newCount > total { start = total - newCount }

        // disable implicit animation – it was the cause of the lag
        withTransaction(Transaction(animation: nil)) {
            visibleSamples = start ..< (start + newCount)
        }
    }

    private func panWaveform(_ value: DragGesture.Value) {
        guard let total = totalFrames, visibleSamples.count < total else { return }
        // “300” controls sensitivity – tweak if you like
        let offset  = Int64((value.translation.width / 300) * Double(visibleSamples.count))
        var start   = dragStartVisibleSamples.lowerBound - offset
        if start < 0 { start = 0 }
        if start + Int64(visibleSamples.count) > total {
            start = total - Int64(visibleSamples.count)
        }
        visibleSamples = start ..< (start + Int64(visibleSamples.count))
    }


    private func zoomToGroup(_ group: TransientGroup) {
        guard let totalFrames = totalFrames, totalFrames > 0 else { return }

        // Add some padding to the view
        let paddingFrames = Int64(Double(group.endFrame - group.startFrame) * 0.1)
        
        let startFrame = max(0, group.startFrame - paddingFrames)
        let endFrame = min(totalFrames, group.endFrame + paddingFrames)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            visibleSamples = startFrame..<endFrame
        }
    }
    
    private func handleDoubleClick(at location: CGPoint, geometry: GeometryProxy) {
        guard let totalFrames = totalFrames else { return }
        
        // Convert click position to frame position
        let normalizedX = location.x / geometry.size.width
        let frameInVisible = Int64(normalizedX * Double(visibleSamples.count))
        let framePosition = visibleSamples.lowerBound + frameInVisible
        
        if isGroupsMode {
            // In groups mode, add transient to selected group
            if let selectedGroupId = groupManager.selectedGroupId,
               let group = groupManager.groups.first(where: { $0.id == selectedGroupId }) {
                // Check if click is within the group bounds
                if framePosition >= group.startFrame && framePosition <= group.endFrame {
                    groupManager.addTransient(to: selectedGroupId, at: framePosition)
                }
            }
        } else {
            // In standard mode, add marker
            let normalizedPosition = Double(framePosition) / Double(totalFrames)
            if !markers.contains(normalizedPosition) {
                markers.append(normalizedPosition)
                markers.sort()
            }
        }
    }
    
    // --- Waveform Loading and Processing ---
    @MainActor
    private func loadAudioAndWaveform() async {
        print("Loading audio data for: \(audioFileURL.path)")
        isLoadingWaveform = true
        waveformRMSData = []
        rawAudioData = []
        markers = []
        
        do {
            let file = try AVAudioFile(forReading: audioFileURL)
            self.audioFile = file
            let frameCount = file.length
            self.totalFrames = frameCount
            self.visibleSamples = 0..<frameCount
            
            let duration = Double(frameCount) / (file.processingFormat.sampleRate)
            self.audioInfo = String(format: "Duration: %.2f s | Rate: %.0f Hz | Frames: %lld",
                                    duration, file.processingFormat.sampleRate, frameCount)
            
            // The rest of this function is for transient detection, not visualization
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
                throw NSError(domain: "AudioLoadError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create buffer"])
            }
            try file.read(into: buffer)
            
            guard let floatChannelData = buffer.floatChannelData else {
                 throw NSError(domain: "AudioLoadError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not get float channel data"])
            }
            
            let channelPtr = floatChannelData[0]
            let audioDataCopy = [Float](UnsafeBufferPointer(start: channelPtr, count: Int(buffer.frameLength)))
            self.rawAudioData = audioDataCopy
            
            // Create SampleBuffer for Waveform view
            self.sampleBuffer = SampleBuffer(samples: audioDataCopy)
            
            // Calculate peak amplitude for normalization
            let peak = audioDataCopy.map { abs($0) }.max() ?? 1.0
            self.peakAmplitude = peak
            
            // This can be simplified or run in background
            let samplesPerPixel = 1024
            let displaySamplesCount = max(1, Int(buffer.frameLength) / samplesPerPixel)
            var rmsSamples = [Float](repeating: 0.0, count: displaySamplesCount)
            
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<displaySamplesCount {
                    let startFrame = i * samplesPerPixel
                    let endFrame = min(startFrame + samplesPerPixel, audioDataCopy.count)
                    if endFrame > startFrame {
                        let block = audioDataCopy[startFrame..<endFrame]
                        let sumOfSquares = block.reduce(0.0) { $0 + ($1 * $1) }
                        rmsSamples[i] = sqrt(sumOfSquares / Float(block.count))
                    }
                }
                DispatchQueue.main.async {
                    self.waveformRMSData = rmsSamples
                    self.isLoadingWaveform = false
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.audioInfo = "Error loading audio: \(error.localizedDescription)"
                self.isLoadingWaveform = false
                self.viewModel.showError("Failed to load audio file: \(error.localizedDescription)")
            }
        }
    }
    
    // --- UPDATED: Transient Detection Logic ---

        /// Detects transients, stores original indices, calculates initial positions, and populates the map.
        private func detectAndSetTransients() {
            guard !waveformRMSData.isEmpty else {
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
            guard !markerOriginalIndexMap.isEmpty, !waveformRMSData.isEmpty, waveformRMSData.count > 1 else {
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
        private func mapAllSegmentsAsRoundRobin(targetNote: Int, targetLayer: Int, vm: SamplerViewModel) {
            let segments = calculateSegments()
            guard !segments.isEmpty else {
                 vm.showError("Cannot map: No segments defined (add markers first).")
                 return
             }
            print("View: Requesting mapping of \(segments.count) segments as round robin to note \(targetNote), layer \(targetLayer)")
            // --- Pass targetLayer to the updated ViewModel function ---
            vm.mapSegmentsAsRoundRobin(
                segments: segments,
                midiNote: targetNote,
                sourceURL: self.audioFileURL,
                targetLayerIndex: targetLayer // Pass the selected index
            )
            // -------------------------------------------------------
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

        
        // MARK: - Groups Export
        
        private func exportGroups() {
            let groupSegments = groupManager.generateSegments()
            
            for (group, segments) in groupSegments {
                guard let targetNote = group.targetMidiNote else {
                    print("Skipping group '\(group.name)' - no target note assigned")
                    continue
                }
                
                // Convert SampleSegments to AudioSegments
                let audioSegments = segments.map { segment in
                    SamplerViewModel.AudioSegment(
                        startFrame: segment.startFrame,
                        endFrame: segment.endFrame,
                        sampleRate: audioFile?.processingFormat.sampleRate ?? 44100
                    )
                }
                
                // Map segments to the target note with velocity layers and round robins
                viewModel.importGroupSegments(
                    segments: audioSegments,
                    targetNote: targetNote,
                    velocityLayers: group.velocityLayers,
                    roundRobins: group.roundRobins,
                    sourceURL: audioFileURL
                )
            }
            
            dismiss()
        }

    // NOTE: For brevity, the large block of unchanged helper functions for transient detection,
    // segment calculation, and mapping have been omitted here. You should paste them back
    // into this location from your original file. They start with `detectAndSetTransients()`
    // and end with `exportGroups()`.
}


// --- The GroupDetailView, PreviewProvider, and Color extension are also unchanged ---
// ... (GroupDetailView, AudioSegmentEditorView_Previews, etc.) ...

// NOTE: The `GroupDetailView` and `AudioSegmentEditorView_Previews` structs, along with the
// `Color` extension and any other helpers at the bottom of the original file, should also
// be pasted back in here. They do not need modification.

// The custom `WaveformScrollView`, `WaveformContainerView`, and `WaveformContainerViewDelegate`
// from the original file should be completely removed.

// MARK: - Group Detail View

struct GroupDetailView: View {
    let group: TransientGroup
    @ObservedObject var groupManager: TransientGroupManager
    let audioFile: AVAudioFile?
    let waveformRMSData: [Float]
    let rawAudioData: [Float]
    let totalFrames: Int64?
    
    @State private var sensitivity: Double = 0.5
    @State private var isDetectingTransients = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group header
            HStack {
                Circle()
                    .fill(Color(group.color) ?? .blue)
                    .frame(width: 12, height: 12)
                
                Text(group.name)
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    groupManager.deleteGroup(group.id)
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Configuration
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Velocity Layers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Stepper("\(group.velocityLayers)", value: Binding(
                        get: { group.velocityLayers },
                        set: { newValue in
                            var updatedGroup = group
                            updatedGroup.velocityLayers = newValue
                            groupManager.updateGroup(updatedGroup)
                        }
                    ), in: 1...16)
                }
                
                VStack(alignment: .leading) {
                    Text("Round Robins")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Stepper("\(group.roundRobins)", value: Binding(
                        get: { group.roundRobins },
                        set: { newValue in
                            var updatedGroup = group
                            updatedGroup.roundRobins = newValue
                            groupManager.updateGroup(updatedGroup)
                        }
                    ), in: 1...16)
                }
                
                VStack(alignment: .leading) {
                    Text("Target Note")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: Binding(
                        get: { group.targetMidiNote },
                        set: { newValue in
                            var updatedGroup = group
                            updatedGroup.targetMidiNote = newValue
                            groupManager.updateGroup(updatedGroup)
                        }
                    )) {
                        Text("Not Assigned").tag(nil as Int?)
                        ForEach(0...127, id: \.self) { note in
                            Text(midiNoteName(note))
                                .tag(note as Int?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 100)
                }
            }
            
            Divider()
            
            // Transient detection
            VStack(alignment: .leading, spacing: 8) {
                Text("Transients: \(group.transients.count) / \(group.expectedSegments)")
                    .font(.caption)
                
                HStack {
                    Text("Sensitivity:")
                        .font(.caption)
                    
                    Slider(value: $sensitivity, in: 0.01...1.0)
                        .frame(width: 150)
                    
                    Button("Auto-Detect") {
                        detectTransients()
                    }
                    .disabled(waveformRMSData.isEmpty || isDetectingTransients)
                    
                    if group.transients.count > 0 {
                        Button("Clear") {
                            var updatedGroup = group
                            updatedGroup.transients.removeAll()
                            groupManager.updateGroup(updatedGroup)
                        }
                    }
                }
            }
            
            if group.isComplete {
                Label("Ready to export", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func detectTransients() {
        isDetectingTransients = true
        
        // Convert sensitivity to threshold (inverted - higher sensitivity = lower threshold)
        let threshold = Float(1.0 - sensitivity)
        
        // Extract RMS data for the group's range
        // Need to convert frame positions to RMS sample indices
        let samplesPerRMSPoint = max(1, Int(totalFrames ?? 1) / waveformRMSData.count)
        let startRMSIndex = Int(group.startFrame) / samplesPerRMSPoint
        let endRMSIndex = min(Int(group.endFrame) / samplesPerRMSPoint, waveformRMSData.count)
        
        guard startRMSIndex >= 0 && startRMSIndex < endRMSIndex && endRMSIndex <= waveformRMSData.count else {
            print("Invalid group range for transient detection: startRMS=\(startRMSIndex), endRMS=\(endRMSIndex), rmsCount=\(waveformRMSData.count)")
            isDetectingTransients = false
            return
        }
        
        let groupRMSData = Array(waveformRMSData[startRMSIndex..<endRMSIndex])
        print("Detecting transients in group '\(group.name)' with \(groupRMSData.count) RMS samples, threshold=\(threshold)")
        
        // Pass the samples per RMS point so transient positions can be converted back to frames
        groupManager.autoDetectTransients(for: group.id, audioData: groupRMSData, threshold: threshold, samplesPerDataPoint: samplesPerRMSPoint)
        
        isDetectingTransients = false
    }
    
    private func midiNoteName(_ note: Int) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 2
        let noteIndex = note % 12
        return "\(noteNames[noteIndex])\(octave)"
    }
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

        return AudioSegmentEditorView(audioFileURL: dummyURL, targetNoteOverride: nil)
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


// MARK: - NSColor Extension

extension NSColor {
    convenience init?(hex: String) {
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
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
