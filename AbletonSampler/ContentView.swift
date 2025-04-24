// File: AbletonSampler/AbletonSampler/ContentView.swift
import SwiftUI
import UniformTypeIdentifiers // Needed for UTType constants
import CoreMIDI // Needed for MIDIEndpointRef

// --- Make URL Identifiable for use with .sheet(item:) ---
extension URL: Identifiable {
    public var id: String { absoluteString }
}

// --- NEW: Identifiable struct for Detail View Segmentation Request ---
struct SegmentationRequestInfo: Identifiable {
    let id = UUID() // Conformance to Identifiable
    let url: URL
    let note: Int
}
// ---------------------------------------------------------------------

// --- NEW: Enum to manage what detail view to show --- 
enum DetailPresentationState: Identifiable {
    case none
    case showingSample(id: UUID)
    case addingSample(note: Int)

    var id: String {
        switch self {
        case .none: return "none"
        case .showingSample(let id): return "sample_\(id)"
        case .addingSample(let note): return "add_\(note)"
        }
    }
}
// -------------------------------------------------------

struct ContentView: View {
    // Use @StateObject for the initial creation and ownership in the main view
    // if this ContentView is the root where the ViewModel is created.
    // If the ViewModel is created elsewhere (e.g., in the App struct) and passed down,
    // @EnvironmentObject is correct.
    // Assuming @EnvironmentObject is appropriate based on typical App structure.
    @EnvironmentObject var viewModel: SamplerViewModel // Access the shared view model
    // --- ADD EnvironmentObject for MIDIManager --- 
    @EnvironmentObject var midiManager: MIDIManager

    // Define grid layout
    let columns: [GridItem] = Array(repeating: .init(.flexible()), count: 12) // 12 columns for notes 0-11

    // --- State for Selected Note/Sample/Add --- 
    // Make the state Optional for .sheet(item:)
    @State private var detailPresentation: DetailPresentationState? = nil
    // -------------------------------------------

    // --- State for Audio Segment Editor --- 
    @State private var fileURLForEditor: URL? = nil
    @State private var editorDropTargeted: Bool = false

    // --- State for MIDI Destination (currently unused in UI) ---
    @State private var selectedMidiDestinationEndpoint: MIDIEndpointRef? = nil

    var body: some View {
        VStack(spacing: 0) { 
            // --- Top Header Row --- 
            HStack {
                Text("Ableton Sampler Patch Builder")
                    .font(.title)
                
                Spacer() // Push title and drop zone apart
                
                // --- Use the extracted editor drop zone view --- 
                editorDropZoneView
                // ---------------------------------------------------

            }
            .padding(.horizontal) // Padding for the whole HStack
            .padding(.top) // Padding above the HStack
            .padding(.bottom, 5) // Space below header
            // -------------------------

            // --- Piano Roll --- 
            PianoKeyboardView(keys: $viewModel.pianoKeys) { selectedKeyId in
                // --- UPDATED LOGIC: Set detailPresentation state (non-nil to show sheet) --- 
                 if let firstPartID = viewModel.multiSampleParts.first(where: { $0.keyRangeMin == selectedKeyId })?.id {
                     self.detailPresentation = .showingSample(id: firstPartID)
                     print("Selected Key: \(selectedKeyId), Found Sample Part ID: \(firstPartID). Setting state to .showingSample")
                 } else {
                     self.detailPresentation = .addingSample(note: selectedKeyId)
                     print("Selected Key: \(selectedKeyId), No samples found. Setting state to .addingSample")
                 }
            }
            .frame(height: 250)
            .padding(.bottom)

            Divider()

            // --- Conditionally Display Placeholder --- 
            // Check if detailPresentation is nil
            if detailPresentation == nil {
                 Text("Click a key to view/add samples.")
                     .foregroundColor(.secondary)
                     .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Show status based on the non-nil state (which is about to trigger the sheet)
                // Use optional chaining or force unwrap safely if needed, but description should handle it
                Text("Key \(detailPresentation!.description) selected...") 
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // --- Save Button --- 
            Spacer() // Pushes save button to the bottom
            Button("Save ADV File") { 
                print("Save ADV File button tapped")
                viewModel.saveAdvFile()
            }
            .padding()
            .buttonStyle(.borderedProminent)

        } // End of main VStack
        .frame(minWidth: 800, minHeight: 750)
        // --- Apply Alerts and Sheets to the main VStack --- 
        .alert("Error", isPresented: $viewModel.showingErrorAlert, presenting: viewModel.errorAlertMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
        .alert("Multiple Files Dropped", isPresented: $viewModel.showingVelocitySplitPrompt,
               presenting: viewModel.pendingDropInfo) { dropInfo in 
            Button("Separate Zones") { viewModel.processMultiDrop(mode: .separate) }
            Button("Velocity Crossfades") { viewModel.processMultiDrop(mode: .crossfade) }
            Button("Round Robin") { viewModel.processMultiDropAsRoundRobin() }
            Button("Cancel", role: .cancel) { viewModel.pendingDropInfo = nil }
        } message: { dropInfo in
            let noteNameString = viewModel.pianoKeys.first { $0.id == dropInfo.midiNote }?.name ?? "Note \(dropInfo.midiNote)"
            Text("You dropped \(dropInfo.fileURLs.count) files onto \(noteNameString). How should the velocity range be split?")
        }
        .sheet(item: $fileURLForEditor, onDismiss: { print("Main editor sheet dismissed.") }) { url in
            // Present normal editor (no targetNoteOverride)
            AudioSegmentEditorView(audioFileURL: url, targetNoteOverride: nil)
                .environmentObject(viewModel)
        }
        // --- Sheet for Detail Presentation State (now using Binding<DetailPresentationState?>) --- 
        .sheet(item: $detailPresentation) { state in // state is non-nil DetailPresentationState here
            // Sheet modifier handles setting detailPresentation back to nil on dismiss.
            
            switch state {
            case .showingSample(let id):
                // Find index safely using the captured ID
                if let selectedIndex = viewModel.multiSampleParts.firstIndex(where: { $0.id == id }) {
                    SampleDetailView(samplePart: $viewModel.multiSampleParts[selectedIndex])
                        .environmentObject(viewModel) // Pass environment object
                } else {
                    // Should not happen if state logic is correct, but handle gracefully
                    Text("Error: Sample part with ID \(id) not found.")
                        .padding()
                }
            case .addingSample(let note):
                AddSampleView(midiNoteNumber: note)
                    .environmentObject(viewModel) // Pass environment object
            case .none:
                // This case should not be presented by .sheet(item:), 
                // but is required for exhaustiveness.
                EmptyView()
            }
        }
        /* REMOVED: Item-based sheet for segmentationRequestInfo */
    }

    // --- Extracted Editor Drop Zone View --- 
    @ViewBuilder
    private var editorDropZoneView: some View {
        VStack {
            HStack {
                Image(systemName: "waveform.path.badge.plus")
                    .font(.title3)
                Text("Drop WAV to Edit Segments")
                    .font(.caption) // Smaller font
            }
        }
        .frame(width: 250, height: 50) // Reduced size
        .background(editorDropTargeted ? Color.accentColor : Color.secondary.opacity(0.2))
        .cornerRadius(8) // Slightly smaller radius
        .padding(.vertical, 5) // Add some vertical padding within HStack
        .onDrop(of: [UTType.fileURL], isTargeted: $editorDropTargeted) { providers, _ -> Bool in
            guard providers.count == 1 else { 
                viewModel.showError("Please drop only a single WAV file here.")
                return false 
            }
            return handleEditorDrop(providers: providers)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(editorDropTargeted ? Color.white : Color.clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.1), value: editorDropTargeted)
        // Note: .sheet modifiers moved to the main VStack
    }
    // -----------------------------------------
    
    // --- Drop Handler for the Editor Zone --- 
    private func handleEditorDrop(providers: [NSItemProvider]) -> Bool {
        // We already ensured providers.count == 1 in the onDrop closure
        guard let provider = providers.first else {
            return false // Should not happen
        }

        var collectedURL: URL? = nil
        let dispatchGroup = DispatchGroup()

        print("Handling drop for editor zone...")

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            dispatchGroup.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                defer { dispatchGroup.leave() }

                if let error = error {
                    print("    Editor Drop Error loading item: \(error)")
                    return
                }

                var fileURL: URL?
                if let urlData = item as? Data {
                    fileURL = URL(dataRepresentation: urlData, relativeTo: nil)
                } else if let url = item as? URL {
                    fileURL = url
                }

                if let url = fileURL, url.pathExtension.lowercased() == "wav" {
                    print("    Editor Drop: Successfully loaded WAV URL: \(url.path)")
                    collectedURL = url
                } else if let url = fileURL {
                    print("    Editor Drop: Skipping non-WAV file: \(url.lastPathComponent)")
                    // Explicitly show error if it's a non-WAV file
                    viewModel.showError("Only single WAV files can be dropped here.")
                } else {
                    print("    Editor Drop Error: Could not obtain URL.")
                    viewModel.showError("Could not read the dropped file.")
                }
            }
        } else {
            print("  Editor Drop: Provider does not conform to fileURL.")
            viewModel.showError("The dropped item was not a file.")
            return false
        }

        dispatchGroup.notify(queue: .main) {
            if let url = collectedURL {
                print("Editor Drop: Valid WAV file received. Setting URL state to trigger sheet.")
                self.fileURLForEditor = url
            } else {
                // Error messages are now shown earlier during processing
                print("Editor Drop: No valid WAV URL collected or processed.")
            }
        }
        return true
    }
}

// --- NEW: Add description to DetailPresentationState for debugging --- 
extension DetailPresentationState: CustomStringConvertible {
    var description: String {
        switch self {
        case .none: return "None"
        case .showingSample(let id): return "Showing Sample \(id.uuidString.prefix(8))"
        case .addingSample(let note): return "Adding Sample to Note \(note)"
        }
    }
}
// ---------------------------------------------------------------------

// Preview for development
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        // --- Initialize ViewModel ---
        let previewViewModel = SamplerViewModel()
        // --- Initialize MIDIManager ---
        // Use the actual MIDIManager if possible, or a mock for isolated preview
        let previewMidiManager = MIDIManager() // Correct initialization

        // Add dummy data for previewing different states if necessary
        // previewViewModel.multiSampleParts.append(MultiSamplePartData(...))

        // --- Inject both into the environment ---
        ContentView()
            .environmentObject(previewViewModel)
            .environmentObject(previewMidiManager) // Inject MIDIManager
    }
}
