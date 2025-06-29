import SwiftUI

struct BatchImportView: View {
    @EnvironmentObject var viewModel: SamplerViewModel
    @Environment(\.dismiss) var dismiss
    
    let fileURLs: [URL]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Batch Import")
                .font(.largeTitle)
                .padding()
            
            Text("\(fileURLs.count) files selected")
                .font(.title2)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(fileURLs, id: \.self) { url in
                        HStack {
                            Text(url.lastPathComponent)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .frame(maxHeight: 300)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .padding()
                
                Spacer()
                
                Button("Test Parse") {
                    testParsing()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .frame(width: 600, height: 500)
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            print("SimpleBatchImportView appeared with \(fileURLs.count) files:")
            for url in fileURLs {
                print("  - \(url.lastPathComponent)")
            }
        }
    }
    
    private func testParsing() {
        print("\n=== Testing File Name Parsing ===")
        for url in fileURLs {
            let parsed = FileNameParser.parse(fileName: url.lastPathComponent)
            print("\nFile: \(url.lastPathComponent)")
            print("  Sample Name: \(parsed.sampleName)")
            print("  MIDI Note: \(parsed.midiNote ?? -1)")
            print("  Velocity: \(parsed.velocityRange?.min ?? -1)-\(parsed.velocityRange?.max ?? -1)")
            print("  Round Robin: \(parsed.roundRobinIndex ?? -1)")
        }
    }
}