import SwiftUI

/// A view presented when the user clicks on a piano key with no samples assigned.
/// This view will allow dropping a WAV file, performing transient detection,
/// and assigning the resulting segments to the selected key.
struct AddSampleView: View {
    @EnvironmentObject var viewModel: SamplerViewModel
    @Environment(\.dismiss) var dismiss

    let midiNoteNumber: Int

    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Sample(s) to \(SamplerViewModel.noteNumberToName(midiNoteNumber)) (MIDI Note \(midiNoteNumber))")
                .font(.title)

            // --- Drop Zone Placeholder --- 
            VStack {
                Image(systemName: "doc.badge.plus")
                    .font(.largeTitle)
                Text("Drop WAV File Here")
                    .font(.headline)
                Text("(Transient detection will run automatically)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(isDropTargeted ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.1))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [10]))
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
                return true // Indicate drop was handled
            }

            Text("Alternatively, choose a file:")

            Button {
                // TODO: Implement file picker
                print("File picker not implemented yet.")
            } label: {
                Label("Choose WAV File...", systemImage: "folder")
            }

            Spacer() // Pushes cancel button down

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)

        }
        .padding()
        .frame(minWidth: 400, minHeight: 450)
        .alert("Error", isPresented: $viewModel.showingErrorAlert) { // Use simple alert presentation
             Button("OK", role: .cancel) { viewModel.clearError() }
         } message: {
             Text(viewModel.errorAlertMessage ?? "An unknown error occurred.")
         }
    }

    // --- Drop Handling Logic --- 
    private func handleDrop(providers: [NSItemProvider]) -> Void {
        guard let provider = providers.first else {
            viewModel.showError("No item provider found.")
            return
        }

        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                DispatchQueue.main.async {
                    if let error = error {
                        viewModel.showError("Failed to load dropped item: \(error.localizedDescription)")
                        return
                    }
                    guard let fileURL = url else {
                        viewModel.showError("Dropped item could not be loaded as a URL.")
                        return
                    }
                    
                    guard fileURL.pathExtension.lowercased() == "wav" else {
                        viewModel.showError("Only WAV files are supported.")
                        return
                    }

                    print("Valid WAV file dropped: \(fileURL.lastPathComponent) for note \(midiNoteNumber)")
                    // TODO: Initiate transient detection & mapping process here
                    // Example: Trigger a function in ViewModel
                    // Task {
                    //     await viewModel.processDroppedFileForSegmentation(fileURL: fileURL, targetNote: midiNoteNumber)
                    //     dismiss() // Dismiss after processing (or show results)
                    // }
                    viewModel.showError("Transient detection from drop not implemented yet.")
                    // dismiss() // Keep open for now
                }
            }
        } else {
             viewModel.showError("Cannot load the dropped item as a file URL.")
        }
    }
}

// MARK: - Preview
struct AddSampleView_Previews: PreviewProvider {
    static var previews: some View {
        AddSampleView(midiNoteNumber: 60) // Example: C4
            .environmentObject(SamplerViewModel()) // Provide a dummy ViewModel
    }
} 