import SwiftUI
import UniformTypeIdentifiers

struct BatchImportView: View {
    @EnvironmentObject var viewModel: SamplerViewModel
    @Environment(\.dismiss) var dismiss
    
    let fileURLs: [URL]
    @State private var parsedSamples: [ParsedSampleInfo] = []
    @State private var groupedByNote: [Int: [ParsedSampleInfo]] = [:]
    @State private var selectedNotes: Set<Int> = []
    @State private var isProcessing = false
    @State private var importProgress: Double = 0.0
    @State private var currentStatus = "Ready to import"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 10) {
                Text("Batch Import Samples")
                    .font(.title2)
                    .bold()
                    .foregroundColor(.primary) // Ensure visibility
                
                Text("\(fileURLs.count) files selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            
            Divider()
            
            // Preview Table
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(Array(groupedByNote.keys.sorted()), id: \.self) { note in
                        NoteGroupView(
                            note: note,
                            samples: groupedByNote[note] ?? [],
                            isSelected: selectedNotes.contains(note),
                            onToggle: { toggleNoteSelection(note) }
                        )
                    }
                    
                    // Unparsed files (no MIDI note detected)
                    let unparsedSamples = parsedSamples.filter { $0.midiNote == nil }
                    if !unparsedSamples.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Unrecognized Files", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                                .foregroundColor(.orange)
                            
                            ForEach(unparsedSamples, id: \.originalFileName) { sample in
                                Text(sample.originalFileName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 20)
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Status and Progress
            if isProcessing {
                VStack(spacing: 10) {
                    ProgressView(value: importProgress)
                        .progressViewStyle(.linear)
                    
                    Text(currentStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Select All") {
                    selectedNotes = Set(groupedByNote.keys)
                }
                .disabled(isProcessing)
                
                Button("Import Selected") {
                    performImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedNotes.isEmpty || isProcessing)
            }
            .padding()
        }
        .frame(width: 700, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            print("BatchImportView appeared with \(fileURLs.count) files")
            parseSamples()
        }
    }
    
    private func parseSamples() {
        print("Parsing \(fileURLs.count) files...")
        parsedSamples = FileNameParser.parseBatch(fileURLs: fileURLs)
        print("Parsed \(parsedSamples.count) samples")
        
        groupedByNote = FileNameParser.groupByNote(parsedSamples)
        print("Grouped into \(groupedByNote.count) notes: \(groupedByNote.keys.sorted())")
        
        // Auto-select all parsed notes
        selectedNotes = Set(groupedByNote.keys)
        print("Selected \(selectedNotes.count) notes for import")
    }
    
    private func toggleNoteSelection(_ note: Int) {
        if selectedNotes.contains(note) {
            selectedNotes.remove(note)
        } else {
            selectedNotes.insert(note)
        }
    }
    
    private func performImport() {
        isProcessing = true
        importProgress = 0.0
        
        Task {
            let totalSamples = selectedNotes.reduce(0) { sum, note in
                sum + (groupedByNote[note]?.count ?? 0)
            }
            var processedCount = 0
            
            for note in selectedNotes.sorted() {
                guard let samples = groupedByNote[note] else { continue }
                
                await MainActor.run {
                    currentStatus = "Importing samples for note \(note)..."
                }
                
                // Group samples by velocity and round robin
                var velocityGroups: [String: [ParsedSampleInfo]] = [:]
                
                for sample in samples {
                    let velocityKey = sample.velocityRange.map { "\($0.min)-\($0.max)" } ?? "0-127"
                    if velocityGroups[velocityKey] == nil {
                        velocityGroups[velocityKey] = []
                    }
                    velocityGroups[velocityKey]?.append(sample)
                }
                
                // Prepare batch import data
                var batchSamples: [(url: URL, velocityRange: (min: Int, max: Int), roundRobinIndex: Int)] = []
                
                print("DEBUG: Processing \(samples.count) samples for note \(note)")
                
                for sample in samples {
                    print("DEBUG: Looking for file: \(sample.originalFileName)")
                    // Add .wav extension if not present
                    let fileNameToMatch = sample.originalFileName.hasSuffix(".wav") ? sample.originalFileName : "\(sample.originalFileName).wav"
                    if let url = fileURLs.first(where: { $0.lastPathComponent == fileNameToMatch }) {
                        let velocityRange = sample.velocityRange ?? (min: 0, max: 127)
                        let rrIndex = sample.roundRobinIndex ?? 1
                        print("DEBUG: Found URL, velocity: \(velocityRange), RR: \(rrIndex)")
                        batchSamples.append((
                            url: url,
                            velocityRange: velocityRange,
                            roundRobinIndex: rrIndex
                        ))
                    } else {
                        print("DEBUG: Could not find URL for \(sample.originalFileName)")
                    }
                }
                
                print("DEBUG: Collected \(batchSamples.count) samples for import")
                
                await MainActor.run {
                    currentStatus = "Importing \(batchSamples.count) samples for note \(note)..."
                    
                    // Use the new batch import method
                    viewModel.importBatchSamples(for: note, samples: batchSamples)
                }
                
                processedCount += samples.count
                await MainActor.run {
                    importProgress = Double(processedCount) / Double(totalSamples)
                }
            }
            
            await MainActor.run {
                currentStatus = "Import complete!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    dismiss()
                }
            }
        }
    }
}

// Sub-view for each note group
struct NoteGroupView: View {
    let note: Int
    let samples: [ParsedSampleInfo]
    let isSelected: Bool
    let onToggle: () -> Void
    
    @State private var isExpanded = false
    
    var noteName: String {
        // Convert MIDI note to name (C3 = 60 convention)
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 2
        let noteIndex = note % 12
        return "\(noteNames[noteIndex])\(octave)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                
                Button(action: { isExpanded.toggle() }) {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        
                        Text("Note \(note) (\(noteName))")
                            .font(.headline)
                        
                        Text("\(samples.count) sample\(samples.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(samples, id: \.originalFileName) { sample in
                        HStack {
                            Text(sample.originalFileName)
                                .font(.caption)
                            
                            Spacer()
                            
                            if let vel = sample.velocityRange {
                                Text("v\(vel.min)-\(vel.max)")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            
                            if let rr = sample.roundRobinIndex {
                                Text("RR\(rr)")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.leading, 40)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}