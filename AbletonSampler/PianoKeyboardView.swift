import SwiftUI
import UniformTypeIdentifiers // For UTType.fileURL

// PianoKey struct and generatePianoKeys() function are now defined globally (moved from SamplerViewModel.swift)

struct PianoKeyboardView: View {
    @Binding var keys: [PianoKey]
    // Access ViewModel through environment for KeyView drop handling
    @EnvironmentObject var viewModel: SamplerViewModel

    let viewHeight: CGFloat = 150

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            let whiteKeys = keys.filter { $0.isWhite }
            let totalWidth = whiteKeys.reduce(0) { $0 + $1.width }

            ZStack(alignment: .topLeading) {
                // --- White Keys --- 
                ForEach(keys.filter { $0.isWhite }) { key in
                     KeyView(key: key)
                         .offset(x: key.xOffset)
                         .environmentObject(viewModel)
                 }
                 // --- Black Keys --- 
                 ForEach(keys.filter { !$0.isWhite }) { key in
                     KeyView(key: key)
                         .offset(x: key.xOffset, y: 0)
                         .zIndex(key.zIndex)
                         .environmentObject(viewModel)
                 }
            }
            .frame(width: max(totalWidth, 10), height: viewHeight)
            // --- Remove Alignment Frame --- 
            // .frame(maxWidth: .infinity, alignment: .leading) // Removed
        }
        .frame(height: viewHeight + 30)
        .border(Color.gray)
    }
}

// Represents the visual appearance of a single key - NOW with Drop Target
struct KeyView: View {
    @EnvironmentObject var viewModel: SamplerViewModel // Access ViewModel for drop handling
    let key: PianoKey
    @State private var isTargeted: Bool = false // Visual feedback for drop

    var body: some View {
        VStack(spacing: 0) {
             Rectangle()
                .fill(keyColor)
                .frame(width: key.width, height: key.height)
                .border(Color.black, width: 1)
                .overlay(
                    // Sample Indicator
                    key.hasSample ? Circle().fill(Color.red.opacity(0.7)).frame(width: 10, height: 10).padding(5) : nil,
                    alignment: .bottom
                )
                // Drop target removed from Rectangle

            // Key Labels below white keys
            if key.isWhite {
                 Text(key.name)
                    .font(.system(size: 10))
                    .frame(width: key.width)
                    .padding(.top, 2)
                    .background(Color.white.opacity(0.001)) // Make label area part of drop target if needed
            } else {
                EmptyView()
            }
        }
         // --- Apply Drop Target and Feedback to VStack --- 
        .contentShape(Rectangle()) // Make the whole VStack the drop target area
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers -> Bool in
             handleDrop(providers: providers)
        }
        .background(isTargeted ? Color.blue.opacity(0.5) : Color.clear) // Slightly more opaque feedback
        .animation(.easeInOut(duration: 0.1), value: isTargeted)
        .frame(width: key.width) // Ensure VStack takes key width
        // Adjust height based on key type to contain label
        .frame(height: key.isWhite ? 140 : key.height) 
    }

    private var keyColor: Color {
        key.isWhite ? Color.white : Color.black
    }

    // --- Drop Handling Logic (similar to old KeyZoneView) --- 
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var collectedURLs: [URL] = []
        let dispatchGroup = DispatchGroup()
        var loadErrors = false

        print("Handling drop for \\(providers.count) providers on key \\(key.id) ('\\(key.name)')...")

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                dispatchGroup.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                    defer { dispatchGroup.leave() }

                    if let error = error {
                        print("    Error loading dropped item: \\(error)")
                        loadErrors = true
                        return
                    }

                    var fileURL: URL?
                    if let urlData = item as? Data {
                        fileURL = URL(dataRepresentation: urlData, relativeTo: nil)
                    } else if let url = item as? URL {
                        fileURL = url
                    }

                    if let url = fileURL, url.pathExtension.lowercased() == "wav" {
                        print("    Successfully loaded WAV URL: \\(url.path)")
                        collectedURLs.append(url)
                    } else if let url = fileURL {
                        print("    Skipping non-WAV file: \\(url.lastPathComponent)")
                    } else {
                        print("    Error processing dropped item - could not obtain URL.")
                        loadErrors = true
                    }
                }
            } else {
                print("  Provider does not conform to fileURL. Skipping.")
            }
        }

        dispatchGroup.notify(queue: .main) {
            print("All drop providers finished loading for key \\(key.id). Collected \\(collectedURLs.count) WAV URLs.")
            if !collectedURLs.isEmpty {
                // Call ViewModel's handler
                viewModel.handleDroppedFiles(midiNote: key.id, fileURLs: collectedURLs)
            } else {
                print("No valid WAV URLs collected from the drop on key \\(key.id).")
                if loadErrors {
                    viewModel.showError("Some dropped files could not be read.")
                }
                // Optionally show specific error if NO URLs were collected but drop was attempted
                if providers.count > 0 && collectedURLs.isEmpty && !loadErrors {
                     viewModel.showError("Only WAV files can be dropped onto keys.")
                 }
            }
        }
        return true // Indicate drop attempt was accepted
    }
    // -------------------------------------------------------
}

// Preview Provider (Ensure generatePianoKeys is accessible)
struct PianoKeyboardView_Previews: PreviewProvider {
    @State static var previewKeys: [PianoKey] = {
        var keys = generatePianoKeys() // Should work now as it's global
        if let indexC4 = keys.firstIndex(where: { $0.id == 60 }) { keys[indexC4].hasSample = true }
        if let indexA0 = keys.firstIndex(where: { $0.id == 21 }) { keys[indexA0].hasSample = true }
         if let indexC_2 = keys.firstIndex(where: { $0.id == 0 }) { keys[indexC_2].hasSample = true }
        if let indexG8 = keys.firstIndex(where: { $0.id == 127 }) { keys[indexG8].hasSample = true }
        return keys
    }()
    // Create a dummy ViewModel for the preview environment
    @StateObject static var previewViewModel = SamplerViewModel()

    static var previews: some View {
        PianoKeyboardView(keys: $previewKeys)
            .environmentObject(previewViewModel) // Provide the ViewModel
            .previewLayout(.fixed(width: 1000, height: 250)) // Wider preview
    }
} 