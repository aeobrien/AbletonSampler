import SwiftUI
import UniformTypeIdentifiers // For UTType.fileURL

// PianoKey struct and generatePianoKeys() function are now defined globally (moved from SamplerViewModel.swift)

struct PianoKeyboardView: View {
    @Binding var keys: [PianoKey]
    @EnvironmentObject var viewModel: SamplerViewModel

    // --- ADD Action Handler --- 
    let onKeySelect: (Int) -> Void // Closure to call when a key is selected
    // -------------------------

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height

            ScrollView(.horizontal, showsIndicators: true) {
                let whiteKeys = keys.filter { $0.isWhite }
                let totalWidth = whiteKeys.reduce(0) { $0 + ($1.width ?? 0) }

                ZStack(alignment: .topLeading) {
                    // --- White Keys --- 
                    HStack(spacing: 0) {
                        ForEach(keys.filter { $0.isWhite }) { key in
                            // Pass availableHeight and keySelectAction down
                            KeyView(key: key, availableHeight: availableHeight) { selectedKeyId in
                                // Call the closure passed from ContentView
                                onKeySelect(selectedKeyId)
                            }
                            .environmentObject(viewModel)
                        }
                    }

                    // --- Black Keys --- 
                    ForEach(keys.filter { !$0.isWhite }) { key in
                        // Pass availableHeight and keySelectAction down
                        KeyView(key: key, availableHeight: availableHeight) { selectedKeyId in
                             // Call the closure passed from ContentView
                             onKeySelect(selectedKeyId)
                         }
                        .offset(x: key.xOffset ?? 0, y: 0)
                        .zIndex(1)
                        .environmentObject(viewModel)
                    }
                }
                .frame(width: max(totalWidth, 10), height: availableHeight)
            } 
            .frame(height: geometry.size.height)
            .border(Color.gray)
        }
    }
}

// Represents the visual appearance of a single key - NOW with keySelectAction
struct KeyView: View {
    @EnvironmentObject var viewModel: SamplerViewModel
    let key: PianoKey
    let availableHeight: CGFloat
    // --- UPDATED Action Handler --- 
    let keySelectAction: (Int) -> Void // Closure to trigger key selection
    // -----------------------------

    @State private var isTargeted: Bool = false

    private var keyLabelSpace: CGFloat {
        key.isWhite ? 25 : 0
    }

    private var keyDrawingHeight: CGFloat {
        let heightForDrawing = availableHeight - keyLabelSpace
        let positiveHeight = max(0, heightForDrawing)
        let visuallyShorterHeight = max(0, positiveHeight - 40)
        return key.isWhite ? visuallyShorterHeight : visuallyShorterHeight * 0.65
    }

    var body: some View {
        VStack(spacing: 0) {
             Rectangle()
                .fill(keyColor)
                .frame(width: key.width, height: keyDrawingHeight)
                .border(Color.black, width: 1)
                .overlay(
                    key.hasSample ? Circle().fill(Color.red.opacity(0.7)).frame(width: 10, height: 10).padding(5) : nil,
                    alignment: .bottom
                )

            if key.isWhite {
                 Text(key.name)
                    .font(.system(size: 10))
                    .frame(width: key.width, height: keyLabelSpace)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 2)
                    .background(Color.white.opacity(0.001))
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers -> Bool in
             handleDrop(providers: providers)
        }
        .background(isTargeted ? Color.blue.opacity(0.5) : Color.clear)
        .animation(.easeInOut(duration: 0.1), value: isTargeted)
        // --- Updated Tap Gesture --- 
        .onTapGesture {
             // Always call the action, passing the key ID
             print("Key \(key.id) ('\(key.name)') tapped, calling keySelectAction.")
             keySelectAction(key.id)
         }
         // ------------------------
        .frame(width: key.width)
        .frame(height: availableHeight, alignment: .top)
    }

    private var keyColor: Color {
        key.isWhite ? Color.white : Color.black
    }

    // --- Drop Handling Logic (remains unchanged) ---
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var collectedURLs: [URL] = []
        let dispatchGroup = DispatchGroup()
        var loadErrors = false

        print("Handling drop for \(providers.count) providers on key \(key.id) ('\(key.name)')...")

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                dispatchGroup.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                    defer { dispatchGroup.leave() }

                    if let error = error {
                        print("    Error loading dropped item: \(error)")
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
                        print("    Successfully loaded WAV URL: \(url.path)")
                        collectedURLs.append(url)
                    } else if let url = fileURL {
                        print("    Skipping non-WAV file: \(url.lastPathComponent)")
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
            print("All drop providers finished loading for key \(key.id). Collected \(collectedURLs.count) WAV URLs.")
            if !collectedURLs.isEmpty {
                viewModel.handleDroppedFiles(midiNote: key.id, fileURLs: collectedURLs)
            } else {
                print("No valid WAV URLs collected from the drop on key \(key.id).")
                if loadErrors {
                    viewModel.showError("Some dropped files could not be read.")
                }
                if providers.count > 0 && collectedURLs.isEmpty && !loadErrors {
                     viewModel.showError("Only WAV files can be dropped onto keys.")
                 }
            }
        }
        return true
    }
}

// Preview Provider remains the same
struct PianoKeyboardView_Previews: PreviewProvider {
    @State static var previewKeys: [PianoKey] = {
        var keys = generatePianoKeys()
        if let indexC4 = keys.firstIndex(where: { $0.id == 60 }) { keys[indexC4].hasSample = true }
        if let indexA0 = keys.firstIndex(where: { $0.id == 21 }) { keys[indexA0].hasSample = true }
         if let indexC_2 = keys.firstIndex(where: { $0.id == 0 }) { keys[indexC_2].hasSample = true }
        if let indexG8 = keys.firstIndex(where: { $0.id == 127 }) { keys[indexG8].hasSample = true }
        return keys
    }()
    @StateObject static var previewViewModel = SamplerViewModel()

    static var previews: some View {
        PianoKeyboardView(keys: $previewKeys) { selectedKeyId in
            // Example action for preview
            print("Preview: Key \(selectedKeyId) selected")
        }
            .environmentObject(previewViewModel)
            .frame(height: 250)
            .previewLayout(.fixed(width: 1000, height: 300))
    }
} 