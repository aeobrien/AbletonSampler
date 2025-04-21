import SwiftUI
import CoreMIDI
import os.log

/// A simple view representing one octave of a MIDI keyboard.
struct KeyboardView: View {
    /// Shared MIDI manager instance.
    @ObservedObject var midiManager: MIDIManager
    /// The currently selected MIDI destination endpoint to send notes to.
    var selectedDestinationEndpoint: MIDIEndpointRef?

    /// The current octave for the keyboard (Middle C4 = 60, so C3 = 48). Default is Octave 3.
    @State private var currentOctave: Int = 3 // C3 = 48

    // Logger for debugging keyboard actions
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.AbletonSampler", category: "KeyboardView")

    /// Note names within an octave.
    let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    /// Indicates which notes are sharp/flat (black keys).
    let sharpNotes = [false, true, false, true, false, false, true, false, true, false, true, false]

    var body: some View {
        VStack {
            // Octave selection
            HStack {
                Button("Octave Down") {
                    if currentOctave > -1 { // MIDI notes can go down to 0
                        currentOctave -= 1
                        logger.debug("Octave decreased to: \(self.currentOctave)")
                    }
                }
                Spacer()
                Text("Octave: \(currentOctave)")
                    .font(.headline)
                Spacer()
                Button("Octave Up") {
                    // Max MIDI note is 127. C9 is 120. Let's cap octave at 9.
                    if currentOctave < 9 {
                        currentOctave += 1
                        logger.debug("Octave increased to: \(self.currentOctave)")
                    }
                }
            }
            .padding(.horizontal)

            // Keyboard keys layout
            HStack(spacing: 2) { // Reduced spacing for keys
                ForEach(0..<noteNames.count, id: \.self) { noteIndex in
                    Button {
                        playNote(noteIndex: noteIndex)
                    } label: {
                        Text(noteNames[noteIndex])
                            .font(.system(size: 10)) // Smaller font for key names
                            .frame(maxWidth: .infinity) // Make buttons expand
                            .frame(height: sharpNotes[noteIndex] ? 60 : 100) // Black keys shorter
                            .background(sharpNotes[noteIndex] ? Color.black : Color.white)
                            .foregroundColor(sharpNotes[noteIndex] ? .white : .black)
                            .border(Color.gray, width: 1) // Add border for definition
                    }
                    .disabled(selectedDestinationEndpoint == nil) // Disable if no output selected
                }
            }
            .frame(height: 110) // Set a fixed height for the keyboard area
            .padding(.horizontal)

            // Display selected destination (optional, for debugging/confirmation)
            if let dest = selectedDestinationEndpoint, let info = midiManager.midiDestinations.first(where: { $0.id == dest }) {
                 Text("Sending to: \(info.name)")
                     .font(.caption)
                     .padding(.top, 5)
             } else {
                 Text("Select a MIDI Output")
                     .font(.caption)
                     .foregroundColor(.red)
                     .padding(.top, 5)
             }
        }
        .padding(.vertical)
    }

    /// Calculates the MIDI note number and sends Note On/Off messages.
    /// - Parameter noteIndex: The index (0-11) of the note within the octave.
    private func playNote(noteIndex: Int) {
        guard let destination = selectedDestinationEndpoint else {
            logger.warning("Attempted to play note but no destination selected.")
            return
        }

        // Calculate MIDI Note Number: C4 = 60. Formula: 12 * (octave + 1) + noteOffset
        let noteNumber = 12 * (currentOctave + 1) + noteIndex

        // Ensure note number is within valid MIDI range (0-127)
        guard (0...127).contains(noteNumber) else {
            logger.error("Calculated note number \(noteNumber) is outside valid MIDI range (0-127).")
            return
        }

        let noteUInt8 = UInt8(noteNumber)
        let velocity: UInt8 = 100 // Fixed velocity for now
        let channel: UInt8 = 0 // MIDI Channel 1 (0-indexed)

        // --- Create MIDI Note On Message ---
        // Status byte: 0x90 | channel (0x90 for Note On on channel 1)
        let noteOnStatus: UInt8 = 0x90 | channel
        let noteOnData: [UInt8] = [noteOnStatus, noteUInt8, velocity]
        logger.debug("Sending Note On: ch=\(channel + 1) note=\(noteUInt8) (\(noteNames[noteIndex])\(currentOctave)) vel=\(velocity) to dest \(destination)")
        midiManager.sendMIDIMessage(data: noteOnData, to: destination)

        // --- Create MIDI Note Off Message ---
        // Status byte: 0x80 | channel (0x80 for Note Off on channel 1)
        // Often, Note On with velocity 0 is also used for Note Off. Let's use 0x80 for clarity.
        let noteOffStatus: UInt8 = 0x80 | channel
        let noteOffVelocity: UInt8 = 0 // Velocity for Note Off is often 0 or release velocity
        let noteOffData: [UInt8] = [noteOffStatus, noteUInt8, noteOffVelocity]

        // --- Send Note Off Slightly Later ---
        // Send Note Off immediately after Note On for a short press effect.
        // For sustained notes, you'd trigger Note Off on touch up / release.
        // Adding a small delay to ensure systems register Note On first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { // 50ms delay
             logger.debug("Sending Note Off: ch=\(channel + 1) note=\(noteUInt8) (\(noteNames[noteIndex])\(currentOctave)) vel=\(noteOffVelocity) to dest \(destination)")
             midiManager.sendMIDIMessage(data: noteOffData, to: destination)
        }
    }
}

// MARK: - Preview

struct KeyboardView_Previews: PreviewProvider {
    // Create a mock MIDIManager for preview purposes
    class MockMIDIManager: MIDIManager {
        override init() {
            super.init()
            // Add some dummy data for preview
            self.midiDestinations = [
                MIDIDeviceInfo(id: 1, name: "Virtual MIDI Output 1"),
                MIDIDeviceInfo(id: 2, name: "Hardware Synth")
            ]
        }
         // Override send to avoid actual MIDI calls in preview
         override func sendMIDIMessage(data: [UInt8], to destination: MIDIEndpointRef) {
              let bytesString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
              print("[Preview] Send MIDI: [\(bytesString)] to Destination ID: \(destination)")
          }
    }

    static var previews: some View {
        // Provide a mock manager and a selected endpoint (optional) for preview
        KeyboardView(midiManager: MockMIDIManager(), selectedDestinationEndpoint: 1)
            .previewLayout(.sizeThatFits) // Adjust preview layout

         KeyboardView(midiManager: MockMIDIManager(), selectedDestinationEndpoint: nil)
              .previewLayout(.sizeThatFits)
              .previewDisplayName("No Destination Selected")
    }
} 