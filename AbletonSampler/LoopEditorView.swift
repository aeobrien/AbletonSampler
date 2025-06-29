import SwiftUI

struct LoopEditorView: View {
    @Binding var samplePart: MultiSamplePartData
    let audioFileURL: URL
    let totalFrames: Int64
    @Environment(\.dismiss) var dismiss
    
    @State private var sustainLoopStart: Int64 = 0
    @State private var sustainLoopEnd: Int64 = 100000
    @State private var sustainLoopEnabled: Bool = false
    @State private var sustainLoopMode: Int = 1
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Loop Point Editor")
                .font(.title)
                .padding(.top)
            
            Text(audioFileURL.lastPathComponent)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
            // Loop Controls
            VStack(alignment: .leading, spacing: 15) {
                Toggle("Enable Sustain Loop", isOn: $sustainLoopEnabled)
                    .font(.headline)
                
                if sustainLoopEnabled {
                    HStack {
                        Text("Loop Mode:")
                        Picker("", selection: $sustainLoopMode) {
                            Text("Forward").tag(1)
                            Text("Ping-Pong").tag(2)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Start: \(sustainLoopStart)")
                            Slider(
                                value: Binding(
                                    get: { Double(sustainLoopStart) },
                                    set: { sustainLoopStart = Int64($0) }
                                ),
                                in: 0...Double(totalFrames)
                            )
                        }
                        
                        VStack(alignment: .leading) {
                            Text("End: \(sustainLoopEnd)")
                            Slider(
                                value: Binding(
                                    get: { Double(sustainLoopEnd) },
                                    set: { sustainLoopEnd = Int64($0) }
                                ),
                                in: Double(sustainLoopStart)...Double(totalFrames)
                            )
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
            
            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Apply") {
                    // Apply the changes
                    if sustainLoopEnabled {
                        samplePart.sustainLoopStart = sustainLoopStart
                        samplePart.sustainLoopEnd = sustainLoopEnd
                        samplePart.sustainLoopMode = sustainLoopMode
                    } else {
                        samplePart.sustainLoopStart = nil
                        samplePart.sustainLoopEnd = nil
                        samplePart.sustainLoopMode = 0
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 600, height: 400)
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            print("LoopEditorView onAppear - file: \(audioFileURL.lastPathComponent), frames: \(totalFrames)")
            // Initialize from existing data
            if let start = samplePart.sustainLoopStart,
               let end = samplePart.sustainLoopEnd {
                sustainLoopStart = start
                sustainLoopEnd = end
                sustainLoopEnabled = samplePart.sustainLoopMode > 0
                sustainLoopMode = samplePart.sustainLoopMode > 0 ? samplePart.sustainLoopMode : 1
                print("Loaded existing loop points: start=\(start), end=\(end), mode=\(samplePart.sustainLoopMode)")
            } else {
                sustainLoopStart = 0
                sustainLoopEnd = min(totalFrames / 2, 100000)
                sustainLoopEnabled = false
                print("No existing loop points, using defaults: start=0, end=\(sustainLoopEnd)")
            }
        }
    }
}
