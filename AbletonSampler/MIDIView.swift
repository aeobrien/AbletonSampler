import SwiftUI
import CoreMIDI // Import CoreMIDI for MIDI functionality

// MARK: - MIDI View

struct MIDIView: View {
    // Receive the shared MIDIManager instance from the environment
    @EnvironmentObject var midiManager: MIDIManager

    var body: some View {
        VStack(alignment: .leading) { // Align content to leading edge
            // --- Display MIDI Sources (Inputs) ---
            Section(header: Text("MIDI Inputs (Sources)").font(.headline)) {
                // Check if the sources list is empty
                if midiManager.midiSources.isEmpty {
                    Text("No MIDI input devices found.")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 5)
                } else {
                    // Iterate over the found sources
                    // Use ForEach with the MIDIDeviceInfo struct
                    ForEach(midiManager.midiSources) { source in
                        HStack {
                            // Display device name
                            Text(source.name)
                            Spacer() // Pushes the connection button to the right
                            // --- Button to connect/disconnect source ---
                            Button { // Action toggles connection
                                if midiManager.connectedSourceIDs.contains(source.id) {
                                    midiManager.disconnectSource(source)
                                } else {
                                    midiManager.connectSource(source)
                                }
                            } label: {
                                // Label changes based on connection status
                                Text(midiManager.connectedSourceIDs.contains(source.id) ? "Disconnect" : "Connect")
                            }
                            // Optional: Add styling to indicate connection status visually
                            .buttonStyle(.bordered)
                            .tint(midiManager.connectedSourceIDs.contains(source.id) ? .red : .blue)
                        }
                        .padding(.vertical, 2) // Add slight vertical padding between rows
                    }
                }
            }
            .padding(.bottom) // Add padding below the sources section

            // --- Display MIDI Destinations (Outputs) ---
            Section(header: Text("MIDI Outputs (Destinations)").font(.headline)) {
                 // Check if the destinations list is empty
                if midiManager.midiDestinations.isEmpty {
                    Text("No MIDI output devices found.")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 5)
                } else {
                    // Iterate over the found destinations
                    ForEach(midiManager.midiDestinations) { destination in
                         HStack {
                             // Display device name
                            Text(destination.name)
                            Spacer()
                            // --- Button to send a test Note On/Off message ---
                            Button("Send Test Note") { // Placeholder action
                                print("Send Test Note tapped for destination: \(destination.name)")
                                // Example: Send Note On C4 (MIDI note 60), velocity 100
                                let noteOn: [UInt8] = [0x90, 60, 100] // Note On, Channel 1, Note 60, Velocity 100
                                midiManager.sendMIDIMessage(data: noteOn, to: destination.id)

                                // Example: Schedule Note Off after a short delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    let noteOff: [UInt8] = [0x80, 60, 0] // Note Off, Channel 1, Note 60, Velocity 0
                                     midiManager.sendMIDIMessage(data: noteOff, to: destination.id)
                                     print("Sent Note Off for: \(destination.name)")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom) // Add padding below the destinations section

            Spacer() // Pushes content towards the top

            // --- Display Last Received Note ---
            Divider() // Add a visual separator
            HStack {
                Text("Last Note Received:")
                    .font(.headline)
                Spacer()
                // Display the note number and name, or "None"
                Text(midiNoteText(midiManager.lastReceivedNoteNumber))
                    .font(.system(.body, design: .monospaced)) // Use monospaced font for notes
                    .foregroundColor(midiManager.lastReceivedNoteNumber != nil ? .primary : .secondary)
            }
            .padding(.top)

            // Placeholder for other MIDI controls or status (kept for potential future use)
            // Text("MIDI Status/Controls Placeholder")
            //     .padding()
            //     .foregroundColor(.gray)

        }
        .navigationTitle("MIDI Setup") // Set the title for the navigation bar
        .padding() // Add padding around the VStack content
        // --- Lifecycle Management (Optional but Recommended) ---
        // .onAppear {
        //     print("MIDIView appeared. Refreshing devices.")
        //     // midiManager.refreshDevices() // Initial refresh is done in init, but can force here
        //     // midiManager.startMonitoring() // If monitoring needs explicit start
        // }
        // .onDisappear {
        //     print("MIDIView disappeared.")
        //     // midiManager.stopMonitoring() // If monitoring needs explicit stop
        //     // Cleanup specific connections if needed
        // }
    }

    // MARK: - Helper Functions

    /// Formats the optional MIDI note number into a display string (e.g., "60 (C4)" or "None").
    private func midiNoteText(_ noteNumber: Int?) -> String {
        guard let note = noteNumber else {
            return "None"
        }
        return "\(note) (\(midiNoteName(note)))"
    }

    /// Converts a MIDI note number (0-127) to its standard name (e.g., C4, F#3).
    private func midiNoteName(_ noteNumber: Int) -> String {
        guard (0...127).contains(noteNumber) else {
            return "Invalid"
        }
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (noteNumber / 12) - 1 // MIDI note 60 (C4) is octave 4
        let noteIndex = noteNumber % 12
        return "\(noteNames[noteIndex])\(octave)"
    }
}

// MARK: - Preview

struct MIDIView_Previews: PreviewProvider {
    static var previews: some View {
        // Wrap in NavigationView for previewing navigation bar title
        NavigationView {
            MIDIView()
                // --- INJECT Mock MIDIManager for Preview --- 
                .environmentObject(KeyboardView_Previews.MockMIDIManager())
        }
    }
} 