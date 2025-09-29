import SwiftUI
import AVFoundation

struct GroupsAssignmentView: View {
    @ObservedObject var groupManager: TransientGroupManager
    @EnvironmentObject var viewModel: SamplerViewModel
    @Binding var selectedGroupId: UUID?
    let audioFile: AVAudioFile?
    let waveformRMSData: [Float]
    let rawAudioData: [Float]?
    let totalFrames: Int64?
    
    @State private var transientSensitivity: Float = 0.1
    
    var body: some View {
        VStack(spacing: 12) {
            if groupManager.groups.isEmpty {
                emptyStateView
            } else if let selectedGroup = groupManager.groups.first(where: { $0.id == selectedGroupId }) {
                selectedGroupDetailView(group: selectedGroup)
            } else {
                Text("Click and drag on the waveform to create a group")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No groups created yet")
                .font(.headline)
            
            Text("Click and drag on the waveform to create a group")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func selectedGroupDetailView(group: TransientGroup) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle()
                    .fill(Color(group.color) ?? .blue)
                    .frame(width: 16, height: 16)
                
                Text(group.name)
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    groupManager.deleteGroup(group.id)
                    selectedGroupId = nil
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mapping Configuration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 20) {
                        VStack(alignment: .leading) {
                            Text("Velocity Layers")
                                .font(.caption)
                            Stepper(value: Binding(
                                get: { group.velocityLayers },
                                set: { newValue in
                                    var updatedGroup = group
                                    updatedGroup.velocityLayers = newValue
                                    groupManager.updateGroup(updatedGroup)
                                }
                            ), in: 1...16) {
                                Text("\(group.velocityLayers)")
                                    .monospacedDigit()
                                    .frame(width: 30)
                            }
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Round Robins")
                                .font(.caption)
                            Stepper(value: Binding(
                                get: { group.roundRobins },
                                set: { newValue in
                                    var updatedGroup = group
                                    updatedGroup.roundRobins = newValue
                                    groupManager.updateGroup(updatedGroup)
                                }
                            ), in: 1...16) {
                                Text("\(group.roundRobins)")
                                    .monospacedDigit()
                                    .frame(width: 30)
                            }
                        }
                    }
                    
                    HStack {
                        Text("Target Note:")
                            .font(.caption)
                        
                        Picker("", selection: Binding(
                            get: { group.targetMidiNote },
                            set: { newValue in
                                var updatedGroup = group
                                updatedGroup.targetMidiNote = newValue
                                groupManager.updateGroup(updatedGroup)
                            }
                        )) {
                            Text("Auto").tag(nil as Int?)
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
                    .frame(height: 80)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transient Detection")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("Auto-Detect") {
                            autoDetectTransients(for: group)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Clear All") {
                            clearTransients(for: group)
                        }
                        .buttonStyle(.bordered)
                        .disabled(group.transients.isEmpty)
                    }
                    
                    HStack {
                        Text("Sensitivity:")
                            .font(.caption)
                        Slider(value: $transientSensitivity, in: 0.01...0.5)
                            .frame(width: 120)
                        Text(String(format: "%.2f", transientSensitivity))
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 35)
                    }
                    
                    Text("Transients: \(group.transients.count) / \(group.expectedSegments)")
                        .font(.caption)
                        .foregroundColor(group.isComplete ? .green : .secondary)
                    
                    Text("Double-click waveform to add markers")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack {
                Button("Export Group") {
                    exportGroup(group)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!group.isComplete)
                
                Spacer()
                
                if !group.isComplete {
                    Text("Add \(group.expectedSegments - group.transients.count) more transients")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func midiNoteName(_ note: Int) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 2
        let noteIndex = note % 12
        return "\(noteNames[noteIndex])\(octave)"
    }
    
    private func autoDetectTransients(for group: TransientGroup) {
        guard !waveformRMSData.isEmpty,
              let totalFrames = totalFrames,
              totalFrames > 0 else { return }
        
        // Calculate which portion of the RMS data corresponds to this group
        let dataCount = waveformRMSData.count
        let startIndex = Int(Double(group.startFrame) / Double(totalFrames) * Double(dataCount))
        let endIndex = Int(Double(group.endFrame) / Double(totalFrames) * Double(dataCount))
        
        guard startIndex < endIndex && endIndex <= dataCount else { return }
        
        // Extract the relevant RMS data for this group
        let groupRMSData = Array(waveformRMSData[startIndex..<endIndex])
        
        // Calculate samples per data point for frame position conversion
        let samplesPerDataPoint = Int(totalFrames) / dataCount
        
        // Use the existing auto-detection method with the user-selected threshold
        groupManager.autoDetectTransients(
            for: group.id,
            audioData: groupRMSData,
            threshold: transientSensitivity,
            samplesPerDataPoint: samplesPerDataPoint
        )
    }
    
    private func clearTransients(for group: TransientGroup) {
        guard let groupIndex = groupManager.groups.firstIndex(where: { $0.id == group.id }) else { return }
        groupManager.groups[groupIndex].transients.removeAll()
    }
    
    private func exportGroup(_ group: TransientGroup) {
        guard let audioFileURL = groupManager.audioFileURL,
              let targetNote = group.targetMidiNote else {
            print("Missing audio file URL or target note for group: \(group.name)")
            return
        }
        
        let groupSegments = groupManager.generateSegments().first(where: { $0.group.id == group.id })
        guard let segments = groupSegments?.segments, !segments.isEmpty else { return }
        
        // Convert SampleSegment to AudioSegment format
        let audioSegments = segments.map { segment in
            SamplerViewModel.AudioSegment(
                startFrame: segment.startFrame,
                endFrame: segment.endFrame,
                sampleRate: groupManager.sampleRate
            )
        }
        
        // Import the segments
        viewModel.importGroupSegments(
            segments: audioSegments,
            targetNote: targetNote,
            velocityLayers: group.velocityLayers,
            roundRobins: group.roundRobins,
            sourceURL: audioFileURL
        )
        
        print("Exported \(segments.count) segments from group: \(group.name)")
    }
}