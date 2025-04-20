// File: HabitStacker/ContentView.swift
import SwiftUI
import UniformTypeIdentifiers // Needed for UTType constants

struct ContentView: View {
    @EnvironmentObject var viewModel: SamplerViewModel // Access the shared view model

    // Define grid layout: 4 columns, flexible width, fixed height
    let columns: [GridItem] = Array(repeating: .init(.flexible()), count: 4)

    var body: some View {
        VStack {
            Text("Ableton Sampler Patch Builder")
                .font(.title)
                .padding(.top)

            // Grid for the sample slots
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    // Iterate over the slots defined in the view model
                    ForEach(viewModel.slots) { slot in
                        SampleSlotView(slot: slot) // Use the dedicated view for each slot
                            .environmentObject(viewModel) // Pass down the view model if needed by the child
                    }
                }
                .padding()
            }

            Spacer() // Pushes the button to the bottom

            // Export button
            Button("Export XML") {
                print("Export button tapped") // Debug print
                viewModel.generateXmlForExport() // Trigger XML generation and modal presentation
            }
            .padding()
            // Present the modal sheet when showingExportModal is true
            .sheet(isPresented: $viewModel.showingExportModal) {
                ExportXmlView(xmlContent: viewModel.generatedXml) // Show the export view
            }
        }
        .frame(minWidth: 500, minHeight: 400) // Set a minimum size for the window
    }
}

// Specific view for displaying and handling drops for a single sample slot
struct SampleSlotView: View {
    @EnvironmentObject var viewModel: SamplerViewModel
    let slot: SampleSlot // The data for this specific slot
    @State private var isTargeted: Bool = false // State for visual feedback on drop target

    var body: some View {
        VStack {
            // Display the MIDI note name (e.g., C-2)
            Text(slot.midiNoteName)
                .font(.headline)
                .padding(.bottom, 2)

            // Display the filename or placeholder text
            Text(slot.fileName ?? "Drop WAV here")
                .font(.caption)
                .lineLimit(1) // Prevent long filenames from wrapping awkwardly
                .truncationMode(.middle)
                .foregroundColor(slot.fileURL == nil ? .secondary : .primary) // Dim placeholder text
                .frame(minHeight: 30) // Ensure minimum height even if text is short

        }
        .padding()
        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 80) // Give the slot some size
        .background(isTargeted ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2)) // Visual feedback for drop target
        .cornerRadius(8)
        // Apply the drop target modifier
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    // Function to handle the dropped items
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // We expect only one item (a single file URL)
        guard let provider = providers.first else { return false }

        // Load the file URL from the provider
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
            // Ensure we are on the main thread for UI updates
            DispatchQueue.main.async {
                if let error = error {
                    print("Error loading dropped item: \(error)")
                    return
                }
                // Get the URL from the item
                guard let urlData = item as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil) else {
                    print("Error processing dropped item as URL")
                    return
                }

                // Check if it's a .wav file before updating the view model
                if url.pathExtension.lowercased() == "wav" {
                     print("Attempting to update slot \(slot.midiNote) with URL: \(url)")
                    // Update the slot in the view model
                    viewModel.updateSlot(midiNote: slot.midiNote, fileURL: url)
                } else {
                    print("Dropped file is not a .wav file: \(url.lastPathComponent)")
                    // Optionally show an alert to the user
                }
            }
        }
        return true // Indicate that the drop was handled
    }
}

// Preview for development
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SamplerViewModel()) // Provide a mock view model for preview
    }
}
