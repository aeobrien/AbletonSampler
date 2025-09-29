import SwiftUI

/// Panel for managing transient groups
struct GroupManagementPanel: View {
    @ObservedObject var groupManager: TransientGroupManager
    @EnvironmentObject var viewModel: SamplerViewModel
    
    @State private var showingAddGroupPopover = false
    @State private var newGroupName = ""
    @State private var selectedStartFrame: Int64 = 0
    @State private var selectedEndFrame: Int64 = 44100
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Transient Groups")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    showingAddGroupPopover = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .popover(isPresented: $showingAddGroupPopover) {
                    addGroupPopover
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // Groups list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(groupManager.groups) { group in
                        GroupRowView(
                            group: group,
                            isSelected: groupManager.selectedGroupId == group.id,
                            groupManager: groupManager,
                            viewModel: viewModel
                        )
                        .onTapGesture {
                            groupManager.selectedGroupId = group.id
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Auto-detect button
            if let selectedGroup = groupManager.groups.first(where: { $0.id == groupManager.selectedGroupId }) {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected: \(selectedGroup.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("Auto-Detect Transients") {
                            autoDetectTransients()
                        }
                        .disabled(groupManager.audioFileURL == nil)
                        
                        Button("Clear Transients") {
                            clearTransients()
                        }
                        .disabled(selectedGroup.transients.isEmpty)
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(width: 300, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var addGroupPopover: some View {
        VStack(spacing: 15) {
            Text("Create New Group")
                .font(.headline)
            
            TextField("Group Name", text: $newGroupName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Start Frame")
                        .font(.caption)
                    TextField("0", value: $selectedStartFrame, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading) {
                    Text("End Frame")
                        .font(.caption)
                    TextField("44100", value: $selectedEndFrame, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            
            HStack {
                Button("Cancel") {
                    showingAddGroupPopover = false
                    newGroupName = ""
                }
                
                Spacer()
                
                Button("Create") {
                    let name = newGroupName.isEmpty ? nil : newGroupName
                    _ = groupManager.createGroup(
                        name: name,
                        startFrame: selectedStartFrame,
                        endFrame: selectedEndFrame
                    )
                    showingAddGroupPopover = false
                    newGroupName = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
    }
    
    private func autoDetectTransients() {
        // This would need access to audio data
        // For now, just a placeholder
        print("Auto-detect transients not yet implemented")
    }
    
    private func clearTransients() {
        guard let selectedId = groupManager.selectedGroupId,
              let groupIndex = groupManager.groups.firstIndex(where: { $0.id == selectedId }) else {
            return
        }
        
        groupManager.groups[groupIndex].transients.removeAll()
    }
}

/// Row view for a single group
struct GroupRowView: View {
    let group: TransientGroup
    let isSelected: Bool
    @ObservedObject var groupManager: TransientGroupManager
    @ObservedObject var viewModel: SamplerViewModel
    
    @State private var isEditing = false
    @State private var editedName = ""
    @State private var editedVelocityLayers = 1
    @State private var editedRoundRobins = 1
    @State private var editedTargetNote: Int?
    
    private var color: Color {
        Color(group.color) ?? .blue
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Color indicator
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                
                // Name
                if isEditing {
                    TextField("Name", text: $editedName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            saveEdits()
                        }
                } else {
                    Text(group.name)
                        .font(.system(.body, design: .rounded))
                }
                
                Spacer()
                
                // Status indicators
                if group.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Text("\(group.transients.count)/\(group.expectedSegments)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Action buttons
                if isSelected {
                    Button(action: {
                        if isEditing {
                            saveEdits()
                        } else {
                            startEditing()
                        }
                    }) {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        groupManager.deleteGroup(group.id)
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Configuration
            if isSelected {
                HStack(spacing: 15) {
                    HStack(spacing: 4) {
                        Text("Layers:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if isEditing {
                            Stepper(value: $editedVelocityLayers, in: 1...16) {
                                Text("\(editedVelocityLayers)")
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                        } else {
                            Text("\(group.velocityLayers)")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                    
                    HStack(spacing: 4) {
                        Text("RR:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if isEditing {
                            Stepper(value: $editedRoundRobins, in: 1...16) {
                                Text("\(editedRoundRobins)")
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                        } else {
                            Text("\(group.roundRobins)")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
                
                // Target assignment
                HStack(spacing: 4) {
                    Text("Target:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if isEditing {
                        Picker("", selection: $editedTargetNote) {
                            Text("None").tag(nil as Int?)
                            ForEach(0...127, id: \.self) { note in
                                Text(midiNoteName(note))
                                    .tag(note as Int?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 80)
                    } else {
                        Text(group.targetMidiNote != nil ? midiNoteName(group.targetMidiNote!) : "Not assigned")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? color.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? color : Color.clear, lineWidth: 1)
                )
        )
    }
    
    private func startEditing() {
        editedName = group.name
        editedVelocityLayers = group.velocityLayers
        editedRoundRobins = group.roundRobins
        editedTargetNote = group.targetMidiNote
        isEditing = true
    }
    
    private func saveEdits() {
        var updatedGroup = group
        updatedGroup.name = editedName
        updatedGroup.velocityLayers = editedVelocityLayers
        updatedGroup.roundRobins = editedRoundRobins
        updatedGroup.targetMidiNote = editedTargetNote
        
        groupManager.updateGroup(updatedGroup)
        isEditing = false
    }
    
    private func midiNoteName(_ note: Int) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 2
        let noteIndex = note % 12
        return "\(noteNames[noteIndex])\(octave)"
    }
}