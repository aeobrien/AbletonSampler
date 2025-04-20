// File: AbletonSampler/AbletonSampler/ContentView.swift
import SwiftUI
import UniformTypeIdentifiers // Needed for UTType constants

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

    // Define grid layout
    let columns: [GridItem] = Array(repeating: .init(.flexible()), count: 12) // 12 columns for notes 0-11

    // --- State for Presenting the Audio Segment Editor --- 
    @State private var fileURLForEditor: URL? = nil // Use this optional URL directly for the sheet
    @State private var editorDropTargeted: Bool = false // Visual feedback for the editor drop zone

    var body: some View {
        VStack {
            Text("Ableton Sampler Patch Builder")
                .font(.title)
                .padding(.top)

            // Grid for the key zones (MIDI notes 0-11)
            ScrollView {
                // Use LazyVGrid for performance with many items
                LazyVGrid(columns: columns, spacing: 15) {
                    // Iterate over the MIDI notes 0 to 11 (C-2 to B-2)
                    // Corrected ForEach id usage
                    ForEach(0..<12, id: \.self) { midiNote in
                        KeyZoneView(midiNote: midiNote)
                            // Pass the viewModel down explicitly if needed by KeyZoneView
                            // EnvironmentObject should already make it available if KeyZoneView declares it.
                            // .environmentObject(viewModel) // Usually not needed if KeyZoneView has @EnvironmentObject
                    }
                }
                .padding()
            }

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
        }
        .frame(minWidth: 600, minHeight: 550) // Increased minHeight for the drop zone
        // Alert for showing save/compression errors
        .alert("Error", isPresented: $viewModel.showingErrorAlert, presenting: viewModel.errorAlertMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
        // --- Corrected Alert for choosing velocity split mode --- 
        .alert("Multiple Files Dropped", isPresented: $viewModel.showingVelocitySplitPrompt,
               // The `presenting` parameter holds the data *when* the alert is shown.
               // The closure receives this data (if not nil) to build the alert's content.
               presenting: viewModel.pendingDropInfo) { dropInfo in
            // Buttons now directly access the 'viewModel' from the environment
            Button("Separate Zones") {
                // Call the ViewModel's method directly
                viewModel.processMultiDrop(mode: .separate)
            }
            Button("Velocity Crossfades") {
                viewModel.processMultiDrop(mode: .crossfade)
            }
            Button("Cancel", role: .cancel) {
                // Best practice: Clear pending info in the ViewModel when cancelled
                // viewModel.cancelPendingDrop() // Consider adding a dedicated cancel func in ViewModel
                viewModel.pendingDropInfo = nil // Direct modification works too
            }
        } message: { dropInfo in
            // Use the 'dropInfo' passed into the closure
            let fileCount = dropInfo.fileURLs.count
            // Use the KeyZoneView's helper for consistency, or define one locally/globally
            let noteName = KeyZoneView.midiNoteNameStatic(for: dropInfo.midiNote)
            Text("You dropped \(fileCount) files onto \(noteName). How should the velocity range be split?")
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

// View for a single Key Zone (MIDI note)
struct KeyZoneView: View {
    // Access the shared ViewModel from the environment
    @EnvironmentObject var viewModel: SamplerViewModel
    let midiNote: Int // The MIDI note this zone represents
    @State private var isTargeted: Bool = false // State for visual feedback on drop target

    // --- Computed Properties using viewModel correctly --- 
    
    // Compute the display text based on mapped samples for this key
    private var displayText: String {
        // Accessing viewModel directly is correct here
        let partsForKey = viewModel.multiSampleParts.filter { $0.keyRangeMin == midiNote }
        if partsForKey.isEmpty {
            return "Drop WAV here"
        } else if partsForKey.count == 1 {
            // Safely unwrap name, provide default
            return partsForKey[0].name
        } else {
            return "\(partsForKey.count) Samples"
        }
    }

    // Compute the background color based on whether samples are mapped
    private var backgroundColor: Color {
        // Accessing viewModel directly is correct here
        let hasSamples = viewModel.multiSampleParts.contains { $0.keyRangeMin == midiNote }
        if isTargeted {
            return Color.blue.opacity(0.4)
        } else if hasSamples {
            return Color.green.opacity(0.3)
        } else {
            return Color.gray.opacity(0.2)
        }
    }

    var body: some View {
        VStack {
            // Display the MIDI note name using the static helper
            Text(KeyZoneView.midiNoteNameStatic(for: midiNote))
                .font(.headline)
                .padding(.bottom, 1)

            // Display the computed text
            Text(displayText)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.tail)
                // Accessing viewModel directly is correct here
                .foregroundColor(viewModel.multiSampleParts.contains { $0.keyRangeMin == midiNote } ? .primary : .secondary)
                .frame(minHeight: 35)
                .padding(.horizontal, 4)
        }
        .padding(EdgeInsets(top: 8, leading: 5, bottom: 8, trailing: 5))
        .frame(minWidth: 80, maxWidth: .infinity, minHeight: 80)
        .background(backgroundColor)
        .cornerRadius(8)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers, _ in // Ignore location for now
            print("Drop detected on key \(midiNote)")
            // Call the instance method correctly
            return self.handleDrop(providers: providers)
        }
    }

    // --- Corrected handleDrop --- 

    // Function to handle the dropped items
    // Returns Bool indicating if the drop was successfully handled (or attempted)
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var collectedURLs: [URL] = []
        let dispatchGroup = DispatchGroup()
        var loadErrors = false // Flag if any provider fails

        print("Handling drop for \(providers.count) providers on key \(midiNote)...")

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

                    // Process the item to get a URL
                    var fileURL: URL?
                    if let urlData = item as? Data {
                        fileURL = URL(dataRepresentation: urlData, relativeTo: nil)
                    } else if let url = item as? URL {
                        fileURL = url // Sometimes the item is directly a URL
                    }

                    // Validate the URL and check if it's a WAV file
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

        // Notify when all async loads are complete
        dispatchGroup.notify(queue: .main) {
            print("All drop providers finished loading. Collected \(collectedURLs.count) WAV URLs.")
            if !collectedURLs.isEmpty {
                // Call the ViewModel's handler - Accessing viewModel directly is correct here
                viewModel.handleDroppedFiles(midiNote: self.midiNote, fileURLs: collectedURLs)
            } else {
                print("No valid WAV URLs collected from the drop.")
                if loadErrors {
                    // Optionally show an error if loading failed for some items
                    // viewModel.showError("Some files could not be read.")
                }
            }
        }

        // Return true immediately, as the handling is async.
        // The actual success is processed in the dispatchGroup.notify block.
        return true
    }

    // --- Static Helper Function --- 
    
    // Static helper function to get MIDI note name (used by ContentView alert as well)
    static func midiNoteNameStatic(for midiNote: Int) -> String {
        let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        // Assuming MIDI note 0 is C-2
        let octave = -2
        let noteIndex = midiNote % 12
        // Ensure index is within bounds (although % 12 should guarantee this for positive ints)
        guard noteIndex >= 0 && noteIndex < notes.count else {
             return "Invalid Note"
        }
        return "\(notes[noteIndex])\(octave)"
    }
}

// Preview for development
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let previewViewModel = SamplerViewModel()
        // Add dummy data for previewing different states
        // previewViewModel.multiSampleParts.append(MultiSamplePartData(...))
        ContentView()
            .environmentObject(previewViewModel)
    }
}
