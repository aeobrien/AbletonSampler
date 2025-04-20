// File: HabitStacker/ExportXmlView.swift
import SwiftUI
#if canImport(AppKit)
import AppKit // Needed for NSPasteboard
#endif


// View to display the generated XML in a modal sheet
struct ExportXmlView: View {
    let xmlContent: String // The XML string to display
    @Environment(\.dismiss) var dismiss // Access dismiss action to close the sheet

    var body: some View {
        VStack(spacing: 15) { // Add spacing between elements
            Text("Generated Ableton Sampler XML")
                .font(.title2) // Slightly smaller title for the modal
                .padding(.top)

            // Use TextEditor for scrollable and selectable text content
            TextEditor(text: .constant(xmlContent))
                .font(.system(.body, design: .monospaced)) // Monospaced font for code
                .border(Color.gray.opacity(0.5), width: 1) // Add a subtle border
                .padding(.horizontal)
                .frame(minHeight: 200, maxHeight: .infinity) // Allow vertical expansion

            HStack { // Layout buttons horizontally
                 Button("Copy to Clipboard") {
                     copyToClipboard(text: xmlContent)
                     // Optionally provide feedback to the user (e.g., change button text briefly)
                 }

                Button("Close") {
                    dismiss() // Close the modal sheet
                }
                .keyboardShortcut(.cancelAction) // Allow closing with Escape key
            }
            .padding(.bottom) // Add padding below buttons
        }
        .padding() // Add padding around the VStack content
        .frame(minWidth: 600, minHeight: 400) // Set a reasonable default size for the modal
    }
    
    // Helper function to copy text to the clipboard (macOS specific)
    private func copyToClipboard(text: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("XML copied to clipboard.")
        #else
        // Handle clipboard for other potential platforms if necessary
        print("Clipboard access not available on this platform.")
        #endif
    }
}

// Preview for development
struct ExportXmlView_Previews: PreviewProvider {
    static var previews: some View {
        // Provide some sample XML for the preview
        ExportXmlView(xmlContent: """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton MajorVersion="5">
            <MultiSampler>
                <!-- Sample XML Content -->
            </MultiSampler>
        </Ableton>
        """)
    }
}
