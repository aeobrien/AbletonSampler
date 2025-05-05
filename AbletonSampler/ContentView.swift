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

    // --- State for Selected Note ---
    @State private var selectedNoteForDetailView: Int? = nil
    // ------------------------------

    // --- State for Audio Segment Editor ---
    @State private var fileURLForEditor: URL? = nil // Uses .sheet(item: $fileURLForEditor)
    @State private var editorDropTargeted: Bool = false

    // --- State for Detail View's Segmentation Request (REPLACED) ---
    // @State private var showingDetailSegmentationSheet: Bool = false
    // @State private var detailSegmentationURL: URL? = nil
    // @State private var detailSegmentationNote: Int? = nil
    @State private var segmentationRequestInfo: SegmentationRequestInfo? = nil // Use item-based sheet
    // ---------------------------------------------------------------------

    // --- State for MIDI Destination (currently unused in UI) ---
    @State private var selectedMidiDestinationEndpoint: MIDIEndpointRef? = nil

    var body: some View {
        VStack(spacing: 0) {
            // --- Top Header Row ---
            HStack {
                Text("Ableton Sampler Patch Builder")
                    .font(.title)
                
                Spacer() // Push title and drop zone apart
                
                // --- Smaller Drop Target for Audio Segment Editor ---
                VStack {
                    // Simplified content for smaller area
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
                    // Ensure only single file drops are handled here
                    guard providers.count == 1 else {
                        viewModel.showError("Please drop only a single WAV file here.")
                        return false
                    }
                    return handleEditorDrop(providers: providers)
                }
                // Add visual feedback on hover for the drop zone
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(editorDropTargeted ? Color.white : Color.clear, lineWidth: 2)
                )
                .animation(.easeInOut(duration: 0.1), value: editorDropTargeted)
                // -----------------------------------------------------

            }
            .padding(.horizontal) // Padding for the whole HStack
            .padding(.top) // Padding above the HStack
            .padding(.bottom, 5) // Space below header
            // -------------------------

            // --- Piano Roll ---
            PianoKeyboardView(keys: $viewModel.pianoKeys) { selectedKeyId in
                self.selectedNoteForDetailView = selectedKeyId
            }
            .frame(height: 250)
            .environmentObject(viewModel)
            .padding(.bottom)

            Divider()

            // --- Conditionally Display Sample Details ---
            if let selectedNote = selectedNoteForDetailView {
                // REMOVE: No longer need to pre-filter samples here
                // let samplesForNote = viewModel.multiSampleParts.filter { $0.keyRangeMin == selectedNote }
                
                // UPDATE: Call SampleDetailView with only the necessary parameters
                SampleDetailView(midiNote: selectedNote) { url, note in
                    // Action called by SampleDetailView's drop zone
                    print("ContentView: Requesting segmentation sheet for \\(url.lastPathComponent) on note \\(note)")
                    // Set the state variable to trigger the item-based sheet
                    self.segmentationRequestInfo = SegmentationRequestInfo(url: url, note: note)
                }
                // .environmentObject(viewModel) // Redundant as SampleDetailView uses @EnvironmentObject
                .padding(.horizontal)
                .padding(.top) 
            } else {
                 Text("Click a key on the piano roll to see sample details.")
                     .foregroundColor(.secondary)
                     .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // --- REMOVED Original Drop Target Position ---
            // VStack { ... Drop Single WAV File Here ... } was here
            // --- ------------------------------------- ---

            // --- Save Button (Now pushed down by SampleDetailView or Spacer) ---
            Spacer() // Add spacer to push save button down if detail view is short or absent
            Button("Save ADV File") {
                print("Save ADV File button tapped")
                viewModel.saveAdvFile()
            }
            .padding()
            .buttonStyle(.borderedProminent)

        } // End of main VStack
        .frame(minWidth: 800, minHeight: 750)
        // Alert for showing save/compression errors
        .alert("Error", isPresented: $viewModel.showingErrorAlert, presenting: viewModel.errorAlertMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
        // --- Corrected Alert for choosing velocity split mode ---
        .alert("Multiple Files Dropped", isPresented: $viewModel.showingVelocitySplitPrompt,
               presenting: viewModel.pendingDropInfo) { dropInfo in // Corrected: Use viewModel.pendingDropInfo (Data?)
            // --- Action Buttons ---
            Button("Separate Zones") {
                viewModel.processMultiDrop(mode: .separate)
            }
            Button("Velocity Crossfades") {
                viewModel.processMultiDrop(mode: .crossfade)
            }
            Button("Round Robin") {
                viewModel.processMultiDropAsRoundRobin()
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDropInfo = nil // Clear pending info on cancel
            }
            // Ensure NO other statements are here - implicit return of Buttons
        } message: { dropInfo in
            // --- Message View ---
            let noteNameString = viewModel.pianoKeys.first { $0.id == dropInfo.midiNote }?.name ?? "Note \\(dropInfo.midiNote)"
            // Debug logging kept for now
            // print("DEBUG ALERT: dropInfo.midiNote = \\(dropInfo.midiNote)")
            // print("DEBUG ALERT: noteNameString = \\(noteNameString)")
            Text("You dropped \(dropInfo.fileURLs.count) files onto \(noteNameString). How should the velocity range be split?")
        }
        // --- Sheet for MAIN Audio Segment Editor ---
        .sheet(item: $fileURLForEditor, onDismiss: { print("Main editor sheet dismissed.") }) { url in
            // Present normal editor (no targetNoteOverride)
            AudioSegmentEditorView(audioFileURL: url, targetNoteOverride: nil)
                .environmentObject(viewModel)
        }
        // --- Sheet for DETAIL VIEW Segmentation Request (MODIFIED) ---
        .sheet(item: $segmentationRequestInfo, onDismiss: {
            print("Detail segmentation sheet dismissed.")
        }) { info in // The 'info' here is the non-nil SegmentationRequestInfo
            // Present editor with targetNoteOverride set using data from 'info'
            AudioSegmentEditorView(audioFileURL: info.url, targetNoteOverride: info.note)
                .environmentObject(viewModel)
            // REMOVED: No need for the if-let check or fallback text anymore
            /*
            // Ensure URL and Note are available before presenting
            if let url = detailSegmentationURL, let note = detailSegmentationNote {
                // Present editor with targetNoteOverride set
                AudioSegmentEditorView(audioFileURL: url, targetNoteOverride: note)
                    .environmentObject(viewModel)
            } else {
                // Fallback view if state is somehow inconsistent (shouldn't happen)
                Text("Error: Missing data for segment editor.")
            }
             */
        }
        // Removed the duplicate midiNoteName function from ContentView scope
        // Removed the KeyZoneView struct as it's no longer used
    }

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
