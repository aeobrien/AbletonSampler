// File: AbletonSampler/AbletonSampler/ContentView.swift
import SwiftUI
import UniformTypeIdentifiers // Needed for UTType constants
import CoreMIDI // Needed for MIDIEndpointRef

// --- Make URL Identifiable for use with .sheet(item:) ---
extension URL: Identifiable {
    public var id: String { absoluteString }
}

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

    // --- State for Presenting the Audio Segment Editor --- 
    @State private var fileURLForEditor: URL? = nil // Use this optional URL directly for the sheet
    @State private var editorDropTargeted: Bool = false // Visual feedback for the editor drop zone

    // --- ADD State for selected MIDI Destination --- 
    @State private var selectedMidiDestinationEndpoint: MIDIEndpointRef? = nil

    var body: some View {
        // --- ADD NavigationView to enable NavigationLink ---
        NavigationView {
            VStack {
                Text("Ableton Sampler Patch Builder")
                    .font(.title)
                    .padding(.top)

                // --- TEST: Reinstate explicit environmentObject injection --- 
                NavigationLink(destination: MIDIView().environmentObject(midiManager)) { // Re-added explicit injection
                    HStack {
                        Image(systemName: "pianokeys.inverse") // Example MIDI-related icon
                        Text("MIDI Setup")
                    }
                    .padding(.vertical, 5)
                }
                // ----------------------------------------

                // --- ADD MIDI Output Section --- 
                Text("MIDI Output Control")
                    .font(.headline)
                    .padding(.top)

                Picker("Select MIDI Output:", selection: $selectedMidiDestinationEndpoint) {
                    Text("None").tag(MIDIEndpointRef?.none) // Option for no selection
                    ForEach(midiManager.midiDestinations) { dest in
                        Text(dest.name).tag(MIDIEndpointRef?.some(dest.id))
                    }
                }
                .padding(.horizontal)

                // --- ADD the Keyboard View --- 
                KeyboardView(midiManager: midiManager, selectedDestinationEndpoint: selectedMidiDestinationEndpoint)
                    .padding(.bottom) // Add some space below
                // ----------------------------------------

                // --- Piano Roll (C-2 - G8) ---
                Text("Piano Roll (C-2 - G8)")
                    .font(.headline)
                    .padding(.top)
                PianoKeyboardView(keys: $viewModel.pianoKeys) // Pass the binding
                     // --- REMOVE Horizontal Padding --- 
                     // .padding(.horizontal)
                     .environmentObject(viewModel) // Make sure ViewModel is passed down
                // -------------------------------------

                // --- Drop Target for Audio Segment Editor --- 
                VStack {
                    Text("Drop Single WAV File Here to Edit Segments")
                        .font(.headline)
                        .foregroundColor(editorDropTargeted ? .white : .primary)
                        .padding()
                    Image(systemName: "waveform.path.badge.plus") // Example icon
                        .font(.largeTitle)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(editorDropTargeted ? Color.accentColor : Color.secondary.opacity(0.2))
                .cornerRadius(10)
                .padding([.horizontal, .bottom])
                .onDrop(of: [UTType.fileURL], isTargeted: $editorDropTargeted) { providers, _ -> Bool in
                    handleEditorDrop(providers: providers)
                }

                Spacer() // Pushes the button to the bottom

                // Save button
                Button("Save ADV File") {
                    print("Save ADV File button tapped")
                    viewModel.saveAdvFile() // Trigger the save process
                }
                .padding()
                .buttonStyle(.borderedProminent)
            } // End of VStack
            // --- ADD navigationTitle for the NavigationView ---
            // This title might be less prominent depending on style, but good practice
            .navigationTitle("Sampler Builder")
            // ---------------------------------------------
        }
        .frame(minWidth: 800, minHeight: 750) // Increased size for keyboard + picker
        // Alert for showing save/compression errors
        .alert("Error", isPresented: $viewModel.showingErrorAlert, presenting: viewModel.errorAlertMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
        // --- Corrected Alert for choosing velocity split mode ---
        .alert("Multiple Files Dropped", isPresented: $viewModel.showingVelocitySplitPrompt,
               presenting: viewModel.pendingDropInfo) { dropInfo in
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
        // --- Sheet Modifier using .sheet(item:) --- 
        .sheet(item: $fileURLForEditor, onDismiss: {
            // Optional: Any cleanup needed when the sheet is dismissed
            print("Segment editor sheet dismissed.")
        }) { url in // The non-nil URL is passed directly into this closure
            // Pass the viewModel down through the environment
            AudioSegmentEditorView(audioFileURL: url) // Use the url passed into the closure
                .environmentObject(viewModel)
            // No need for the 'if let' or the fallback Text view anymore
        }
        // Removed the duplicate midiNoteName function from ContentView scope
        // Removed the KeyZoneView struct as it's no longer used
    }

    // --- Drop Handler for the Editor Zone ---
    private func handleEditorDrop(providers: [NSItemProvider]) -> Bool {
        // We only want to handle a single file drop here
        guard providers.count == 1, let provider = providers.first else {
            print("Editor Drop: Requires exactly one item.")
            viewModel.showError("Please drop only a single WAV file onto the editor area.")
            return false // Indicate failure if not exactly one provider
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

                // Validate URL and check for WAV extension
                if let url = fileURL, url.pathExtension.lowercased() == "wav" {
                    print("    Editor Drop: Successfully loaded WAV URL: \(url.path)")
                    collectedURL = url
                } else if let url = fileURL {
                    print("    Editor Drop: Skipping non-WAV file: \(url.lastPathComponent)")
                    collectedURL = nil
                } else {
                    print("    Editor Drop Error: Could not obtain URL.")
                    collectedURL = nil
                }
            }
        } else {
            print("  Editor Drop: Provider does not conform to fileURL.")
            return false // Indicate failure if provider type is wrong
        }

        // Action after loading is complete
        dispatchGroup.notify(queue: .main) {
            if let url = collectedURL {
                print("Editor Drop: Valid WAV file received. Setting URL state to trigger sheet.")
                // --- Set the URL state variable; this will trigger the .sheet(item:) modifier ---
                self.fileURLForEditor = url
            } else {
                print("Editor Drop: No valid WAV URL collected.")
                if providers.count == 1 { // Avoid duplicate errors
                    viewModel.showError("The dropped file was not a valid WAV file.")
                }
            }
        }

        return true // Indicate drop was accepted (async handling follows)
    }
}

// Preview for development
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let previewViewModel = SamplerViewModel()
        // --- ADD Mock MIDIManager from KeyboardView's preview --- 
        let previewMidiManager = KeyboardView_Previews.MockMIDIManager()
        // Add dummy data for previewing different states
        // previewViewModel.multiSampleParts.append(MultiSamplePartData(...))
        ContentView()
            .environmentObject(previewViewModel)
            .environmentObject(previewMidiManager) // --- INJECT MIDIManager into environment ---
    }
}
