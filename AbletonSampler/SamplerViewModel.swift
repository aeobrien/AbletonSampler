// File: AbletonSampler/AbletonSampler/SamplerViewModel.swift
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers // Needed for UTType
import Foundation // Needed for Process, Pipe, FileManager, URL

// MARK: - Piano Key Data Structure (Moved OUTSIDE ViewModel class)

/// Represents a single key on the piano
struct PianoKey: Identifiable {
    let id: Int // MIDI Note Number (0-127)
    let isWhite: Bool
    let name: String // e.g., "C4", "F#3", "A0"
    var hasSample: Bool // Indicates if a sample is mapped to this key

    // --- Geometry Properties - Now Mutable Vars ---
    // These will be assigned values during the generation process.
    var width: CGFloat = 0   // Default value, will be set by generatePianoKeys
    var height: CGFloat = 0  // Default value, will be set by generatePianoKeys
    var xOffset: CGFloat = 0 // Calculated once for layout
    var zIndex: Double = 0   // Default value, will be set by generatePianoKeys (0 for white, 1 for black)
}

// Generates the 128 keys for the full MIDI range (Moved OUTSIDE ViewModel class)
func generatePianoKeys() -> [PianoKey] {
    var keys: [PianoKey] = []
    let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    let whiteKeyWidth: CGFloat = 30
    let blackKeyWidth: CGFloat = 18
    let whiteKeyHeight: CGFloat = 150
    let blackKeyHeight: CGFloat = whiteKeyHeight * 0.6

    // Generate Key Data
    for midiNote in 0...127 {
        let keyIndexInOctave = midiNote % 12
        let noteName = noteNames[keyIndexInOctave]
        let actualOctave = (midiNote / 12) - 2
        let isWhite: Bool
        switch keyIndexInOctave {
            case 1, 3, 6, 8, 10: isWhite = false
            default: isWhite = true
        }
        let keyName = "\(noteName)\(actualOctave)"
        // Initialize with default layout values; they get assigned below
        let key = PianoKey(id: midiNote, isWhite: isWhite, name: keyName, hasSample: false)
        keys.append(key)
    }

    // Calculate Layout
    var currentXOffset: CGFloat = 0
    var lastWhiteKeyIndex: Int? = nil

    for i in 0..<keys.count {
        if keys[i].isWhite {
            keys[i].width = whiteKeyWidth   // Assign correct width
            keys[i].height = whiteKeyHeight // Assign correct height
            keys[i].xOffset = currentXOffset
            keys[i].zIndex = 0              // Assign correct zIndex
            currentXOffset += whiteKeyWidth
            lastWhiteKeyIndex = i
        } else { // Black key
            keys[i].width = blackKeyWidth   // Assign correct width
            keys[i].height = blackKeyHeight // Assign correct height
            keys[i].zIndex = 1              // Assign correct zIndex
            if let lwki = lastWhiteKeyIndex {
                keys[i].xOffset = keys[lwki].xOffset + keys[lwki].width * 0.6
            } else {
                keys[i].xOffset = blackKeyWidth * 0.5
                print("Warning: Black key at index \(i) ('\(keys[i].name)') appeared before any white key.")
            }
        }
    }
    return keys
}

// MARK: - Data Structures for Sample Parts

/// Represents the calculated velocity range for a sample part
struct VelocityRangeData: Hashable {
    // Note: Using Int for simplicity, matching the XML values (0-127)
    let min: Int
    let max: Int
    let crossfadeMin: Int
    let crossfadeMax: Int

    // Default full range
    static let fullRange = VelocityRangeData(min: 0, max: 127, crossfadeMin: 0, crossfadeMax: 127)
}

/// Represents the data needed to generate one <MultiSamplePart> XML element
struct MultiSamplePartData: Identifiable, Hashable {
    // Need Hashable for potential future diffing or set operations
    static func == (lhs: MultiSamplePartData, rhs: MultiSamplePartData) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id = UUID() // Unique identifier for SwiftUI lists etc.
    var name: String
    let keyRangeMin: Int // MIDI note number
    let keyRangeMax: Int // MIDI note number (same as min for single key mapping)
    var velocityRange: VelocityRangeData
    let sourceFileURL: URL // Original URL of the audio file containing the segment
    var segmentStartSample: Int64 // Start frame within the source file
    var segmentEndSample: Int64 // End frame (exclusive) within the source file. Must be provided.

    // --- Path Information (refers to the source file) ---
    var relativePath: String? // Path relative to the 'Samples/Imported' directory (for the source file)
    var absolutePath: String // Absolute path of the source file on the user's system
    var originalAbsolutePath: String // Absolute path of the source file before copying

    // Extracted metadata (primarily from the source file, frameCount adjusted for segment)
    var sampleRate: Double? // Sample rate of the source file
    var fileSize: Int64? // File size in bytes (of the original source file)
    var crc: UInt32? // CRC checksum (placeholder, calculation TBD, likely for source file)
    var lastModDate: Date? // Last modification date (of the source file)
    var originalFileFrameCount: Int64? // Store the frame count of the *original* source file

    // --- Calculated Segment Properties ---
    var segmentFrameCount: Int64 { // Duration of the segment in frames
        max(0, segmentEndSample - segmentStartSample)
    }

    // Default values for other XML fields (can be expanded later)
    var rootKey: Int { keyRangeMin } // Typically same as the key range
    var detune: Int = 0
    var tuneScale: Int = 100
    var panorama: Int = 0
    var volume: Double = 1.0 // Representing <Volume Value="1">
    var link: Bool = false
    // --- Adjusted Sample Start/End for Segment ---
    var sampleStart: Int64 { segmentStartSample } // Correct: Playback starts at the segment's start in the source file
    var sampleEnd: Int64 { segmentEndSample }     // Correct: Playback ends at the segment's end in the source file

    // Nested structures mirroring XML (simplified for now)
    // These would need more complex structs if we needed to configure loops, warp markers etc.
    var sustainLoopMode: Int = 0 // Off
    var releaseLoopMode: Int = 3 // Off (no release sample)
}

// MARK: - Velocity Splitting Mode

enum VelocitySplitMode {
    case separate // Distinct zones, no overlap in core range
    case crossfade // Overlapping zones with crossfades
}

// MARK: - Mapping Mode (NEW)

/// Defines the overall playback mode affecting the MultiSampleMap
enum MappingMode {
    case standard // Default, one sample per trigger (unless velocity zones)
    case roundRobin // Cycle through samples mapped to the same note
}

// MARK: - Sampler View Model

// Manages the state of the sample parts and XML generation
class SamplerViewModel: ObservableObject {

    // --- Published Properties ---

    /// Holds all the individual sample parts that will be included in the ADV file.
    @Published var multiSampleParts: [MultiSamplePartData] = [] {
        // Automatically update piano keys whenever sample parts change
        didSet {
             updatePianoKeySampleStatus()
        }
    }

    /// NEW: Holds the state for the visual piano keyboard.
    @Published var pianoKeys: [PianoKey] = []

    /// Controls the presentation of the modal asking how to split velocities.
    @Published var showingVelocitySplitPrompt = false

    /// Temporarily stores information about the files dropped onto a key zone
    /// while waiting for the user to choose a split mode.
    @Published var pendingDropInfo: (midiNote: Int, fileURLs: [URL])? = nil

    /// Controls the presentation of the save panel.
    @Published var showingSavePanel = false // Kept from original code

    /// Holds the message for any error alert.
    @Published var errorAlertMessage: String? = nil // Kept from original code

    /// Controls the visibility of the error alert.
    @Published var showingErrorAlert = false // Kept from original code

    /// NEW: Tracks the current mapping mode to influence XML generation (e.g., for Round Robin).
    @Published var currentMappingMode: MappingMode = .standard

    /// NEW: Maps a MIDI Note to the desired number of velocity layers for that note
    @Published var noteLayerConfiguration: [Int: Int] = [:]

    /// NEW: Maps a MIDI Note to the maximum number of round robin slots for that note
    @Published var noteRoundRobinConfiguration: [Int: Int] = [:]

    // --- Initialization ---

    init() {
        print("SamplerViewModel initialized.")
        // Initialize piano keys first using the global function
        self.pianoKeys = generatePianoKeys()
        // Now update their status based on any initially loaded multiSampleParts (currently none)
        updatePianoKeySampleStatus()
        print("Initialized \\(pianoKeys.count) piano keys.")
    }

    // MARK: - Piano Key State Update (NEW)

    /// Updates the `hasSample` property for each key in `pianoKeys`
    /// based on the current contents of `multiSampleParts`.
    private func updatePianoKeySampleStatus() {
         // Use a Set for efficient lookup of mapped MIDI notes
         let mappedNotes = Set(multiSampleParts.map { $0.keyRangeMin })

         print("Updating piano key sample status. Mapped notes: \\(mappedNotes)")

         // Create a new array to avoid direct modification issues with @Published during iteration
         var updatedKeys = self.pianoKeys
         var changesMade = false // Track if any key status actually changed

         for i in 0..<updatedKeys.count {
             let keyMidiNote = updatedKeys[i].id
             let keyCurrentlyHasSample = updatedKeys[i].hasSample
             let shouldHaveSample = mappedNotes.contains(keyMidiNote)

             if keyCurrentlyHasSample != shouldHaveSample {
                 updatedKeys[i].hasSample = shouldHaveSample
                 changesMade = true
                 print(" -> Key \\(keyMidiNote) ('\\(updatedKeys[i].name)') status changed to \\(shouldHaveSample)")
             }
         }

         // Only update the @Published property if there were actual changes
         if changesMade {
             // Update on main thread as this might trigger UI changes
             DispatchQueue.main.async {
                 self.pianoKeys = updatedKeys
                 print("Finished updating piano key sample status. Changes applied.")
             }
         } else {
              print("Finished updating piano key sample status. No changes needed.")
         }
    }

    // MARK: - Drop Handling Logic

    /// Handles processing files dropped onto a specific MIDI key zone.
    /// - Parameters:
    ///   - midiNote: The MIDI note number of the target key zone (0-127).
    ///   - fileURLs: An array of URLs for the dropped files.
    func handleDroppedFiles(midiNote: Int, fileURLs: [URL]) {
        // Filter out any non-WAV files
        let wavURLs = fileURLs.filter { $0.pathExtension.lowercased() == "wav" }

        guard !wavURLs.isEmpty else {
            print("No valid .wav files were dropped.")
            // Optionally show an error to the user
            showError("Only .wav files are supported.")
            return
        }

        print("Handling drop of \(wavURLs.count) WAV file(s) onto MIDI note \(midiNote)...")

        if wavURLs.count == 1 {
            // --- Single File Drop ---
            // Process immediately, assigning full velocity range
            print("Single file drop detected. Processing directly.")
            processSingleFileDrop(midiNote: midiNote, fileURL: wavURLs[0])
        } else {
            // --- Multiple File Drop ---
            // Store the information and trigger the prompt
            print("Multiple file drop detected. Storing pending info and showing prompt.")
            pendingDropInfo = (midiNote: midiNote, fileURLs: wavURLs)
            // Use DispatchQueue.main.async to ensure UI updates happen on the main thread
            DispatchQueue.main.async {
                self.showingVelocitySplitPrompt = true
            }
        }
    }

    /// Processes a single dropped WAV file, creating one MultiSamplePartData.
    /// This action resets the note configuration to a single layer/RR.
    private func processSingleFileDrop(midiNote: Int, fileURL: URL) {
        guard let metadata = extractAudioMetadata(fileURL: fileURL) else {
            showError("Could not read metadata for \\(fileURL.lastPathComponent).")
            return
        }

        // Create the single sample part data with full velocity range
        let partData = MultiSamplePartData(
            name: fileURL.deletingPathExtension().lastPathComponent,
            keyRangeMin: midiNote,
            keyRangeMax: midiNote, // Map to single key
            velocityRange: .fullRange, // Single file gets full velocity range
            sourceFileURL: fileURL,
            segmentStartSample: 0,
            segmentEndSample: metadata.frameCount ?? 0,
            relativePath: nil, // Will be set during save
            absolutePath: fileURL.path,
            originalAbsolutePath: fileURL.path,
            sampleRate: metadata.sampleRate,
            fileSize: metadata.fileSize,
            crc: nil, // Placeholder
            lastModDate: metadata.lastModDate,
            originalFileFrameCount: metadata.frameCount
        )

        // Ensure UI updates on the main thread
        DispatchQueue.main.async {
            self.objectWillChange.send()

            // --- Update Configuration --- 
            // A single drop resets the configuration for this note.
            self.noteLayerConfiguration[midiNote] = 1
            self.noteRoundRobinConfiguration[midiNote] = 1
            print("Single Drop: Reset configuration for note \\(midiNote) to 1 layer, 1 RR.")

            // --- Update Sample Parts --- 
            // Remove any existing parts for this key before adding the new one
            self.multiSampleParts.removeAll { $0.keyRangeMin == midiNote }
            self.multiSampleParts.append(partData)
            // `multiSampleParts` didSet will trigger updatePianoKeySampleStatus()
            print("Added single sample part: \\(partData.name) to key \\(midiNote)")
        }
    }


    /// Processes multiple dropped files based on the user's chosen velocity split mode.
    /// Updates the configuration to match the number of files as layers.
    /// - Parameter mode: The `VelocitySplitMode` selected by the user (.separate or .crossfade).
    func processMultiDrop(mode: VelocitySplitMode) {
        print("Processing multi-drop with mode: \\(mode)")
        guard let info = pendingDropInfo else {
            print("Error: No pending drop info found.")
             DispatchQueue.main.async {
                self.pendingDropInfo = nil
                self.showingVelocitySplitPrompt = false
             }
            return
        }

        let midiNote = info.midiNote
        let fileURLs = info.fileURLs
        let numberOfFiles = fileURLs.count

        guard numberOfFiles > 0 else {
             print("Error: No files found in pending drop info.")
             DispatchQueue.main.async {
                 self.pendingDropInfo = nil
                 self.showingVelocitySplitPrompt = false
             }
             return
        }

        // Calculate the velocity ranges based on the chosen mode and number of files
        let velocityRanges = calculateVelocityRanges(numberOfFiles: numberOfFiles, mode: mode)

        // Ensure we got the correct number of ranges
        guard velocityRanges.count == numberOfFiles else {
            print("Error: Mismatch between number of files (\\(numberOfFiles)) and calculated velocity ranges (\\(velocityRanges.count)).")
            showError("Internal error calculating velocity ranges.")
             DispatchQueue.main.async {
                self.pendingDropInfo = nil
                self.showingVelocitySplitPrompt = false
             }
            return
        }

        var newParts: [MultiSamplePartData] = []

        // Create a MultiSamplePartData for each file with its calculated range
        for (index, fileURL) in fileURLs.enumerated() {
            guard let metadata = extractAudioMetadata(fileURL: fileURL) else {
                print("Warning: Could not read metadata for \\(fileURL.lastPathComponent). Skipping this file.")
                continue // Skip this file and proceed with others
            }

            let partData = MultiSamplePartData(
                name: fileURL.deletingPathExtension().lastPathComponent,
                keyRangeMin: midiNote,
                keyRangeMax: midiNote, // Map to single key
                velocityRange: velocityRanges[index], // Assign calculated range
                sourceFileURL: fileURL,
                segmentStartSample: 0,
                segmentEndSample: metadata.frameCount ?? 0,
                relativePath: nil, // Will be set during save
                absolutePath: fileURL.path,
                originalAbsolutePath: fileURL.path,
                sampleRate: metadata.sampleRate,
                fileSize: metadata.fileSize,
                crc: nil, // Placeholder
                lastModDate: metadata.lastModDate,
                originalFileFrameCount: metadata.frameCount
            )
            newParts.append(partData)
            print("Prepared multi-sample part \\(index + 1)/\\(numberOfFiles): \\(partData.name) for key \\(midiNote) with vel range [\\(partData.velocityRange.min)-\\(partData.velocityRange.max)]")
        }

        // Ensure UI updates on the main thread
        DispatchQueue.main.async {
            self.objectWillChange.send()

            // --- Update Configuration --- 
            // Velocity split sets layers = numFiles, RR = 1.
            self.noteLayerConfiguration[midiNote] = numberOfFiles
            self.noteRoundRobinConfiguration[midiNote] = 1
            self.currentMappingMode = .standard // Ensure standard mapping mode
            print("Velocity Split Drop: Set configuration for note \\(midiNote) to \\(numberOfFiles) layers, 1 RR.")

            // --- Update Sample Parts --- 
             // Remove any existing parts for this key before adding the new ones
            self.multiSampleParts.removeAll { $0.keyRangeMin == midiNote }
            self.multiSampleParts.append(contentsOf: newParts)

            // --- Cleanup --- 
            self.pendingDropInfo = nil
            self.showingVelocitySplitPrompt = false
            // `multiSampleParts` didSet will trigger updatePianoKeySampleStatus()
            print("Finished processing multi-drop velocity split. Added \\(newParts.count) parts.")
        }
    }

    /// Processes multiple dropped files as Round Robin samples on a single key.
    /// Updates configuration to 1 layer, N RRs.
    func processMultiDropAsRoundRobin() {
        print("Processing multi-drop as Round Robin...")
        guard let info = pendingDropInfo else {
            print("Error: No pending drop info found for Round Robin processing.")
             DispatchQueue.main.async {
                self.pendingDropInfo = nil
                self.showingVelocitySplitPrompt = false
             }
            return
        }

        let midiNote = info.midiNote
        let fileURLs = info.fileURLs
        let numberOfFiles = fileURLs.count

        guard numberOfFiles > 0 else {
             print("Error: No files found in pending drop info for Round Robin.")
             DispatchQueue.main.async {
                 self.pendingDropInfo = nil
                 self.showingVelocitySplitPrompt = false
             }
             return
        }

        // --- Prepare Parts (all get full velocity range) --- 
        var newPartsData: [MultiSamplePartData] = []
        for (index, fileURL) in fileURLs.enumerated() {
            guard let metadata = extractAudioMetadata(fileURL: fileURL) else {
                print("Warning: Could not read metadata for \\(fileURL.lastPathComponent). Skipping this file for Round Robin.")
                continue // Skip this file
            }

            let partData = MultiSamplePartData(
                name: fileURL.deletingPathExtension().lastPathComponent + "_RR_\\(index + 1)", // Add RR suffix
                keyRangeMin: midiNote,
                keyRangeMax: midiNote,
                velocityRange: .fullRange, // All files get full velocity range
                sourceFileURL: fileURL,
                segmentStartSample: 0,
                segmentEndSample: metadata.frameCount ?? 0,
                relativePath: nil, // Will be set during save
                absolutePath: fileURL.path,
                originalAbsolutePath: fileURL.path,
                sampleRate: metadata.sampleRate,
                fileSize: metadata.fileSize,
                crc: nil, // Placeholder
                lastModDate: metadata.lastModDate,
                originalFileFrameCount: metadata.frameCount
            )
            newPartsData.append(partData)
            print("Prepared RR part \\(index + 1)/\\(numberOfFiles): \\(partData.name) for key \\(midiNote)")
        }

        // --- Add Parts and Update State --- 
        DispatchQueue.main.async {
            self.objectWillChange.send()

            // --- Update Configuration --- 
            // Round Robin sets layers = 1, RR = numFiles.
            self.noteLayerConfiguration[midiNote] = 1
            self.noteRoundRobinConfiguration[midiNote] = numberOfFiles
            self.currentMappingMode = .roundRobin // Set mapping mode for RR
            print("Round Robin Drop: Set configuration for note \\(midiNote) to 1 layer, \\(numberOfFiles) RRs. Set mapping mode.")

            // --- Update Sample Parts --- 
            // First, clear *all* existing parts for the target note before adding RR samples.
            self.multiSampleParts.removeAll { $0.keyRangeMin == midiNote }
            // Add the new Round Robin parts
            self.multiSampleParts.append(contentsOf: newPartsData)

            // --- Cleanup --- 
            self.pendingDropInfo = nil
            self.showingVelocitySplitPrompt = false

             print("Finished processing multi-drop for Round Robin. Added \\(newPartsData.count) parts.")
             // The didSet on multiSampleParts handles the piano key update
        }
    }

    // MARK: - Velocity Range Calculation (PUBLIC visibility)
    public func calculateVelocityRanges(numberOfFiles: Int, mode: VelocitySplitMode) -> [VelocityRangeData] {
        guard numberOfFiles > 0 else { return [] }
        if numberOfFiles == 1 { return [.fullRange] }
        switch mode {
        case .separate: return calculateSeparateVelocityRanges(numberOfFiles: numberOfFiles)
        case .crossfade: return calculateCrossfadeVelocityRanges(numberOfFiles: numberOfFiles)
        }
    }
    public func calculateSeparateVelocityRanges(numberOfFiles: Int) -> [VelocityRangeData] {
        var ranges: [VelocityRangeData] = []
        let totalVelocityRange = 128.0
        let baseWidth = totalVelocityRange / Double(numberOfFiles)
        var currentMin = 0.0
        for i in 0..<numberOfFiles {
            let calculatedMax = currentMin + baseWidth - 1.0
            var zoneMin = Int(currentMin.rounded(.down))
            var zoneMax = Int(calculatedMax.rounded(.down))
            if i == numberOfFiles - 1 { zoneMax = 127 }
            zoneMin = max(0, zoneMin)
            zoneMax = max(zoneMin, zoneMax); zoneMax = min(127, zoneMax)
            let range = VelocityRangeData(min: zoneMin, max: zoneMax, crossfadeMin: zoneMin, crossfadeMax: zoneMax)
            ranges.append(range)
            currentMin = Double(zoneMax) + 1.0
        }
        // Sanity checks omitted for brevity but should be here
        return ranges
     }
    public func calculateCrossfadeVelocityRanges(numberOfFiles: Int) -> [VelocityRangeData] {
        var ranges: [VelocityRangeData] = []
        let totalVelocityRange = 128.0
        let baseWidth = totalVelocityRange / Double(numberOfFiles)
        let overlap = (baseWidth / 2.0)
        var currentMin = 0.0
        for i in 0..<numberOfFiles {
            let coreMin = currentMin
            var coreMax = currentMin + baseWidth - 1.0
            if i == numberOfFiles - 1 { coreMax = 127.0 }
            let crossfadeMin = coreMin - overlap
            let crossfadeMax = coreMax + overlap
            let finalMin = Int(coreMin.rounded(.down))
            var finalMax = Int(coreMax.rounded(.down))
            if i == numberOfFiles - 1 { finalMax = 127 }
            let finalCrossfadeMin = Int(crossfadeMin.rounded(.down))
            var finalCrossfadeMax = Int(crossfadeMax.rounded(.down))
            let clampedMin = max(0, finalMin)
            var clampedMax = min(127, max(clampedMin, finalMax))
            if i == numberOfFiles - 1 { clampedMax = 127 }
            let clampedCrossfadeMin = max(0, finalCrossfadeMin)
            var clampedCrossfadeMax = min(127, max(clampedCrossfadeMin, finalCrossfadeMax))
            let finalClampedCrossfadeMin = min(clampedMin, clampedCrossfadeMin)
            let finalClampedCrossfadeMax = max(clampedMax, clampedCrossfadeMax)
            let effectiveMin = clampedMin
            let effectiveMax = clampedMax
            let effectiveCrossfadeMin = (i == 0) ? effectiveMin : finalClampedCrossfadeMin
            let effectiveCrossfadeMax = (i == numberOfFiles - 1) ? effectiveMax : finalClampedCrossfadeMax
            let finalEffectiveMax = max(effectiveMin, effectiveMax)
            let finalEffectiveCrossfadeMin = max(0, min(effectiveMin, effectiveCrossfadeMin))
            let finalEffectiveCrossfadeMax = min(127, max(effectiveMax, effectiveCrossfadeMax))
            let range = VelocityRangeData( min: effectiveMin, max: finalEffectiveMax, crossfadeMin: finalEffectiveCrossfadeMin, crossfadeMax: finalEffectiveCrossfadeMax )
            ranges.append(range)
            currentMin = coreMax + 1.0
        }
        // Sanity checks omitted for brevity but should be here
        return ranges
    }


    // MARK: - Metadata Extraction

    /// Helper struct to return multiple metadata values.
    // CHANGE private -> internal (or remove 'private')
    internal struct AudioMetadata {
        let sampleRate: Double?
        let frameCount: Int64?
        let fileSize: Int64?
        let lastModDate: Date?
        // Add CRC later if needed
    }

    /// Extracts relevant metadata from an audio file URL.
    /// - Parameter fileURL: The URL of the audio file.
    /// - Returns: An optional `AudioMetadata` struct, or nil if extraction fails.
    // CHANGE private -> internal (or just remove 'private')
    /* private */ func extractAudioMetadata(fileURL: URL) -> AudioMetadata? {
        var sampleRate: Double? = nil
        var frameCount: Int64? = nil
        var fileSize: Int64? = nil
        var lastModDate: Date? = nil

        // Start accessing security-scoped resource if needed (important for sandboxed apps)
        let securityScoped = fileURL.startAccessingSecurityScopedResource()
        defer {
            if securityScoped {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        print("Extracting metadata for: \(fileURL.path)")

        // Get file attributes (size, modification date)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = attributes[.size] as? Int64
            lastModDate = attributes[.modificationDate] as? Date
            print("  -> File Size: \(fileSize ?? -1), Last Mod: \(lastModDate?.description ?? "N/A")")
        } catch {
            print("  -> Error getting file attributes: \(error)")
            // Allow continuing even if attributes fail, but log it.
        }

        // Get audio metadata using AVFoundation
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let format = audioFile.processingFormat
            sampleRate = format.sampleRate
            frameCount = audioFile.length // Length in sample frames
            print("  -> Sample Rate: \(sampleRate ?? -1), Frame Count: \(frameCount ?? -1)")
        } catch {
            print("  -> Error reading audio file metadata (AVAudioFile): \(error)")
            // If we can't read the audio file essentials, we should fail.
            return nil
        }

        // Check if essential data was retrieved
        guard sampleRate != nil, frameCount != nil, fileSize != nil else {
             print("  -> Failed to retrieve all essential metadata.")
             return nil
        }

        return AudioMetadata(sampleRate: sampleRate, frameCount: frameCount, fileSize: fileSize, lastModDate: lastModDate)
    }


    // MARK: - Mapping Mode Control (NEW)

    /// Sets the global mapping mode, influencing XML generation (e.g., Round Robin tags).
    func setMappingMode(_ mode: MappingMode) {
        // Ensure UI updates on the main thread
        DispatchQueue.main.async {
            self.currentMappingMode = mode
            print("SamplerViewModel mapping mode set to: \(mode)")
        }
    }

    // MARK: - XML Generation and Saving

    /// Function to save the generated XML as a gzipped .adv file
    func saveAdvFile() {
        print("Starting .adv file save process...")

        // --- Present Save Panel First ---
        presentSavePanel { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let targetUrl):
                // Proceed with saving only if user confirmed a location
                 print("Save panel succeeded. Target URL: \(targetUrl.path)")
                self.performSave(to: targetUrl)

            case .failure(let error):
                 print("Save panel failed or was cancelled: \(error)")
                 // You might want to show an error, or just do nothing if cancelled.
                 // self.showError("Could not get save location: \(error.localizedDescription)")
            }
        }
    }

    /// Performs the actual saving process after getting the target URL.
    private func performSave(to targetUrl: URL) {
        // The targetUrl is the location for the .adv file itself.
        // We need to create the 'Samples/Imported' directory relative to this.
        let projectDir = targetUrl.deletingLastPathComponent()
        let samplesDir = projectDir.appendingPathComponent("Samples", isDirectory: true)
        let importedDir = samplesDir.appendingPathComponent("Imported", isDirectory: true)

        print("Project directory: \(projectDir.path)")
        print("Samples directory: \(importedDir.path)")

        do {
            try FileManager.default.createDirectory(at: importedDir, withIntermediateDirectories: true, attributes: nil)
            print("Created Samples/Imported directory.")

            // --- Copy Samples and Update Paths ---
            var updatedParts: [MultiSamplePartData] = []
            // Create a mutable copy to work with, assign relative paths
            var currentParts = self.multiSampleParts // Use the @Published array

             for i in 0..<currentParts.count { // Iterate using index
                 let part = currentParts[i]
                 let sourceURL = part.sourceFileURL

                 // Start accessing security-scoped resource for copying
                 let securityScoped = sourceURL.startAccessingSecurityScopedResource()
                 defer { if securityScoped { sourceURL.stopAccessingSecurityScopedResource() } }

                 let destinationFileName = sourceURL.lastPathComponent
                 let destinationURL = importedDir.appendingPathComponent(destinationFileName)
                 // IMPORTANT: Relative path for XML must be relative to the ADV file's location
                 let relativePath = "Samples/Imported/\(destinationFileName)"

                 do {
                     // Copy the file (handle potential overwrites)
                     if FileManager.default.fileExists(atPath: destinationURL.path) {
                         print("File \(destinationFileName) already exists in destination. Attempting to remove existing.")
                         try FileManager.default.removeItem(at: destinationURL)
                     }
                     try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                     print("Copied \(sourceURL.lastPathComponent) to \(relativePath)")

                     // Update the part in the temporary array
                     currentParts[i].relativePath = relativePath
                     currentParts[i].absolutePath = destinationURL.path // Update absolute path too
                     updatedParts.append(currentParts[i]) // Add successfully processed part

                 } catch {
                      print("Error copying file \(sourceURL.lastPathComponent): \(error)")
                      self.showError("Could not copy sample file: \(sourceURL.lastPathComponent). \(error.localizedDescription)")
                      // Decide how to handle this - skip this part? Stop saving?
                      // For now, let's stop the saving process if a copy fails.
                      return
                 }
             }


            // Update the main array *after* processing all parts successfully
            DispatchQueue.main.async {
                self.objectWillChange.send()
                self.multiSampleParts = updatedParts
                print("Updated multiSampleParts array on main thread.")

                // --- Generate XML with updated paths (NOW using the updated array) ---
                print("Generating XML string...")
                let xmlString = self.generateFullXmlString(projectPath: projectDir.path)

                guard let xmlData = xmlString.data(using: .utf8) else {
                    print("Error: Could not convert final XML string to Data.")
                    self.showError("Failed to prepare final data for saving.")
                    return // Exit the async block
                }

                // --- Gzip Compression ---
                print("Attempting gzip compression...")
                // Note: gzipData involves Process which might block the main thread briefly.
                // For large files, consider moving compression to a background thread
                // and then updating UI/writing file back on the main thread.
                // For now, keeping it simple.
                let compressedData = self.gzipData(xmlData)

                guard let finalCompressedData = compressedData else {
                    print("Gzip compression failed.")
                    self.showError("Failed to compress the file.")
                    return // Exit the async block
                }
                print("Gzip compression successful. Compressed size: \(finalCompressedData.count) bytes")

                // --- Write Compressed File ---
                do {
                    try finalCompressedData.write(to: targetUrl, options: .atomicWrite)
                    print("Successfully saved compressed .adv file to \(targetUrl.path)")
                } catch {
                     print("Error writing compressed data to file \(targetUrl.path): \(error)")
                     self.showError("Could not save the file: \(error.localizedDescription)")
                     // No return needed here, error is shown
                }
            }

        } catch {
            print("Error during file saving/copying/compression: \(error)")
            self.showError("An error occurred during saving: \(error.localizedDescription)")
        }
    }

    /// Configures and presents the NSSavePanel.
    /// Calls the completion handler with the result URL or an error.
    private func presentSavePanel(completion: @escaping (Result<URL, Error>) -> Void) {
        let savePanel = NSSavePanel()

        // Use UTType for modern API
        if #available(macOS 11.0, *) {
            // Define the UTType explicitly
            let advUTType = UTType("com.ableton.live-pack.device-preset") ?? UTType.data
            savePanel.allowedContentTypes = [advUTType]
        } else {
            savePanel.allowedFileTypes = ["adv"] // Fallback for older macOS
        }

        savePanel.nameFieldStringValue = "GeneratedSampler.adv"
        savePanel.title = "Save Ableton Sampler File"
        savePanel.message = "Choose a location to save the .adv file and its Samples folder."
        savePanel.canCreateDirectories = true

        // Run the save panel
        savePanel.begin { result in
            DispatchQueue.main.async { // Ensure completion handler is called on main thread
                if result == .OK, let url = savePanel.url {
                    completion(.success(url))
                } else {
                    // Treat cancellation as a non-error scenario for simplicity here
                    print("Save panel cancelled or failed.")
                    // If you need to distinguish cancellation, define a custom error:
                    // enum SaveError: Error { case cancelled }
                    // completion(.failure(SaveError.cancelled))
                    // For now, we don't call the completion handler on cancel.
                }
            }
        }
    }


    /// Compresses data using the command-line gzip tool.
    /// - Parameter data: The Data to compress.
    /// - Returns: Optional compressed Data.
    private func gzipData(_ data: Data) -> Data? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFilename = UUID().uuidString + ".xml"
        let tempFileURL = tempDir.appendingPathComponent(tempFilename)
        var compressedData: Data?

        do {
            try data.write(to: tempFileURL, options: .atomicWrite)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
            // Use -f to force overwrite if temp file somehow exists from previous failed run
            // Use -k to keep the original temp file (we'll delete it manually)
            // Use -c to output to stdout
            process.arguments = ["-c", "-f", "-k", tempFileURL.path]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            let errorPipe = Pipe() // Capture stderr
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

             // Read stderr *before* checking terminationStatus
             let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
             if let errorString = String(data: errorData, encoding: .utf8), !errorString.isEmpty {
                 print("Gzip stderr: \(errorString)")
             }

            if process.terminationStatus == 0 {
                compressedData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                print("Gzip process completed successfully.")
            } else {
                print("Error: gzip process failed with status \(process.terminationStatus)")
            }

        } catch {
            print("Error during gzip process: \(error)")
        }

        // Clean up temporary file
        do {
            try FileManager.default.removeItem(at: tempFileURL)
             print("Removed temporary gzip input file.")
        } catch {
             print("Warning: Could not remove temporary gzip input file at \(tempFileURL.path): \(error)")
        }


        return compressedData
    }


    /// Generates the complete XML structure as a string.
    /// - Parameter projectPath: The absolute path to the directory where the .adv file is saved.
    /// - Returns: A String containing the full ADV XML.
    private func generateFullXmlString(projectPath: String) -> String {
        let samplePartsXml = generateSamplePartsXml(projectPath: projectPath)

        // Determine Round Robin settings based on the current mode
        let roundRobinValue = currentMappingMode == .roundRobin ? "true" : "false"
        let roundRobinModeValue = currentMappingMode == .roundRobin ? "2" : "0" // Defaulting to mode 2 for RR
        let randomSeed = Int.random(in: 1...1000000000)

        // Basic template structure (you might need to adjust based on Ableton version/defaults)
        // Using a simplified structure based on common elements.
        let baseXmlTemplate = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton MajorVersion="5" MinorVersion="12.0_12120" SchemaChangeCount="4" Creator="AbletonSamplerApp" Revision="Generated">
            <MultiSampler>
                <LomId Value="0" />
                <Player>
                    <MultiSampleMap>
                        <SampleParts>
        \(samplePartsXml)
                        </SampleParts>
                        <LoadInRam Value="false" />
                        <LayerCrossfade Value="0" />
                        <SourceContext />
                        <RoundRobin Value="\(roundRobinValue)" />
                        <RoundRobinMode Value="\(roundRobinModeValue)" />
                        <RoundRobinResetPeriod Value="0" />
                        <RoundRobinRandomSeed Value="\(randomSeed)" />
                    </MultiSampleMap>
                    <!-- Add other essential Player elements if needed -->
                </Player>
                <!-- Add other essential MultiSampler elements (Filter, Pitch, Volume etc.) with defaults -->
                <Pitch>
                    <TransposeKey>
                         <Manual Value="0" />
                    </TransposeKey>
                     <TransposeFine>
                         <Manual Value="0" />
                     </TransposeFine>
                     <!-- other Pitch defaults -->
                 </Pitch>
                 <Filter>
                     <IsOn> <Manual Value="true" /> </IsOn>
                     <Slot>
                         <Value>
                             <SimplerFilter Id="0">
                                <Type> <Manual Value="0" /> </Type> <!-- Lowpass -->
                                <Freq> <Manual Value="22000" /> </Freq>
                                <Res> <Manual Value="0" /> </Res>
                                <!-- Other Filter properties like Slope, Drive, etc. would go here -->

                                <!-- Add Filter Envelope if needed -->
                                <!-- <Envelope> ... </Envelope> -->

                                <!-- Add ModByPitch inside SimplerFilter -->
                                <ModByPitch>
                                    <LomId Value="0" />
                                    <Manual Value="0" /> <!-- Ensure Key Tracking defaults to 0 -->
                                    <!-- Add AutomationTarget/ModulationTarget/MidiControllerRange if needed -->
                                </ModByPitch>

                                <!-- other SimplerFilter defaults -->
                             </SimplerFilter>
                         </Value>
                     </Slot>
                 </Filter>
                 <VolumeAndPan>
                     <Volume>
                         <Manual Value="-12" /> <!-- Default volume -->
                     </Volume>
                     <Panorama>
                          <Manual Value="0" />
                     </Panorama>
                     <Envelope> <!-- Basic ADSR Volume Envelope -->
                         <AttackTime> <Manual Value="0.1" /> </AttackTime>
                         <DecayTime> <Manual Value="600" /> </DecayTime>
                         <SustainLevel> <Manual Value="1" /> </SustainLevel>
                         <ReleaseTime> <Manual Value="50" /> </ReleaseTime>
                          <!-- other Env defaults -->
                      </Envelope>
                 </VolumeAndPan>
                 <Globals>
                    <NumVoices Value="32" /> <!-- Polyphony -->
                    <!-- other Global defaults -->
                 </Globals>
                 <ViewSettings>
                    <SelectedPage Value="0" />
                    <ZoneEditorVisible Value="true" />
                 </ViewSettings>
            </MultiSampler>
        </Ableton>
        """
        return baseXmlTemplate
    }


    /// Generates the XML snippet for all the `<MultiSamplePart>` elements.
    /// - Parameter projectPath: The absolute path to the directory where the .adv file is saved.
    /// - Returns: A String containing the XML for all sample parts.
    private func generateSamplePartsXml(projectPath: String) -> String {
        var xmlParts: [String] = []

        // Sort parts for potentially more consistent output (e.g., by key then velocity min)
        let sortedParts = multiSampleParts.sorted {
            if $0.keyRangeMin != $1.keyRangeMin {
                return $0.keyRangeMin < $1.keyRangeMin
            }
            return $0.velocityRange.min < $1.velocityRange.min
        }

        for (index, part) in sortedParts.enumerated() {
            // Ensure we have the necessary data, especially the relative path
            // First, check the optional properties
            guard let relativePath = part.relativePath,
                  let fileSize = part.fileSize,
                  let sampleRate = part.sampleRate,
                  let lastModDate = part.lastModDate else {
                print("Skipping part \(part.name) due to missing optional metadata (relativePath, fileSize, sampleRate, or lastModDate).")
                continue // Skip this part if essential data is missing
            }

            // Access the non-optional computed property directly AFTER checking optionals
            let frameCount = part.segmentFrameCount

            // Now continue with XML generation using frameCount, relativePath, etc.
            // ...

            // Construct the absolute path based on the *saved* location for the XML <Path> tag.
            let absolutePathForXml = part.absolutePath.cleanedForXml()

            // Convert lastModDate to Unix timestamp (integer seconds)
            let lastModTimestamp = Int(lastModDate.timeIntervalSince1970)

            // Placeholder for CRC - needs actual calculation if required by Ableton
            let crcValue = Int(fileSize % 65536) // Simple placeholder based on size

            // Generate the XML for this part
            // Indentation added for readability
            let partXml = """
                            <MultiSamplePart Id="\(index)" InitUpdateAreSlicesFromOnsetsEditableAfterRead="false" HasImportedSlicePoints="false" NeedsAnalysisData="false">
                                <LomId Value="0" />
                                <Name Value="\(part.name.cleanedForXml())" />
                                <Selection Value="false" /> <!-- Default to not selected -->
                                <IsActive Value="true" />
                                <Solo Value="false" />
                                <KeyRange>
                                    <Min Value="\(part.keyRangeMin)" />
                                    <Max Value="\(part.keyRangeMax)" />
                                    <CrossfadeMin Value="\(part.keyRangeMin)" /> <!-- Assuming no key crossfade -->
                                    <CrossfadeMax Value="\(part.keyRangeMax)" />
                                </KeyRange>
                                <VelocityRange>
                                    <Min Value="\(part.velocityRange.min)" />
                                    <Max Value="\(part.velocityRange.max)" />
                                    <CrossfadeMin Value="\(part.velocityRange.crossfadeMin)" />
                                    <CrossfadeMax Value="\(part.velocityRange.crossfadeMax)" />
                                </VelocityRange>
                                <SelectorRange> <!-- Default full selector range -->
                                    <Min Value="0" />
                                    <Max Value="127" />
                                    <CrossfadeMin Value="0" />
                                    <CrossfadeMax Value="127" />
                                </SelectorRange>
                                <RootKey Value="\(part.rootKey)" />
                                <Detune Value="\(part.detune)" />
                                <TuneScale Value="\(part.tuneScale)" />
                                <Panorama Value="\(part.panorama)" />
                                <Volume Value="\(part.volume)" />
                                <Link Value="\(part.link)" />
                                <SampleStart Value="\(part.sampleStart)" />
                                <SampleEnd Value="\(part.sampleEnd)" /> <!-- Use calculated sampleEnd -->
                                <SustainLoop>
                                    <Start Value="0" />
                                    <End Value="\(part.sampleEnd)" /> <!-- Use calculated sampleEnd -->
                                    <Mode Value="\(part.sustainLoopMode)" />
                                    <Crossfade Value="0" />
                                    <Detune Value="0" />
                                </SustainLoop>
                                <ReleaseLoop>
                                    <Start Value="0" />
                                    <End Value="\(part.sampleEnd)" /> <!-- Use calculated sampleEnd -->
                                    <Mode Value="\(part.releaseLoopMode)" />
                                    <Crossfade Value="0" />
                                    <Detune Value="0" />
                                </ReleaseLoop>
                                <SampleRef>
                                    <FileRef>
                                        <RelativePathType Value="6" />
                                        <RelativePath Value="\(relativePath.cleanedForXml())" />
                                        <Path Value="\(absolutePathForXml)" />
                                        <Type Value="2" /> <!-- Type 2 for WAV -->
                                        <LivePackName Value="" />
                                        <LivePackId Value="" />
                                        <OriginalFileSize Value="\(fileSize)" />
                                        <OriginalCrc Value="\(crcValue)" /> <!-- Placeholder CRC -->
                                    </FileRef>
                                    <LastModDate Value="\(lastModTimestamp)" />
                                    <SourceContext />
                                    <SampleUsageHint Value="0" />
                                    <DefaultDuration Value="\(frameCount)" />
                                    <DefaultSampleRate Value="\(Int(sampleRate))" />
                                    <SamplesToAutoWarp Value="1" />
                                </SampleRef>
                                <SlicingThreshold Value="100" />
                                <SlicingBeatGrid Value="4" />
                                <SlicingRegions Value="8" />
                                <SlicingStyle Value="0" />
                                <SampleWarpProperties> <!-- Default Warp Properties -->
                                    <WarpMarkers />
                                    <WarpMode Value="0" />
                                    <GranularityTones Value="30" />
                                    <GranularityTexture Value="65" />
                                    <FluctuationTexture Value="25" />
                                    <ComplexProFormants Value="100" />
                                    <ComplexProEnvelope Value="128" />
                                    <TransientResolution Value="6" />
                                    <TransientLoopMode Value="2" />
                                    <TransientEnvelope Value="100" />
                                    <IsWarped Value="false" />
                                    <Onsets>
                                        <UserOnsets />
                                        <HasUserOnsets Value="false" />
                                    </Onsets>
                                    <TimeSignature>
                                        <TimeSignatures>
                                            <RemoteableTimeSignature Id="0">
                                                <Numerator Value="4" />
                                                <Denominator Value="4" />
                                                <Time Value="0" />
                                            </RemoteableTimeSignature>
                                        </TimeSignatures>
                                    </TimeSignature>
                                    <BeatGrid>
                                        <FixedNumerator Value="1" />
                                        <FixedDenominator Value="16" />
                                        <GridIntervalPixel Value="20" />
                                        <Ntoles Value="2" />
                                        <SnapToGrid Value="true" />
                                        <Fixed Value="false" />
                                    </BeatGrid>
                                </SampleWarpProperties>
                                <InitialSlicePointsFromOnsets />
                                <SlicePoints />
                                <ManualSlicePoints />
                                <BeatSlicePoints />
                                <RegionSlicePoints />
                                <UseDynamicBeatSlices Value="true" />
                                <UseDynamicRegionSlices Value="true" />
                                <AreSlicesFromOnsetsEditable Value="false" />
                            </MultiSamplePart>
            """
            xmlParts.append(partXml)
        } // End of loop

        // Join all parts with indentation that matches the surrounding template
        return xmlParts.joined(separator: "\n                        ") // Ensure indentation matches baseXmlTemplate
    }


    // MARK: - Segment Processing Logic (Moved from Editor)

    /// Adds multiple sample parts based on segments, mapping them to velocity zones on a single note.
    /// Updates configuration to N layers (N=segments), 1 RR.
    /// Called from AudioSegmentEditorView.
    func addSegmentsToNote(segments: [(start: Double, end: Double)], midiNote: Int, sourceURL: URL) {
        print("ViewModel: Adding \\(segments.count) segments from \\(sourceURL.lastPathComponent) to velocity zones on note \\(midiNote).")

        guard !segments.isEmpty else {
            showError("Cannot add segments: No segments provided.")
            return
        }

        // First, get the necessary metadata for frame conversion
        guard let metadata = extractAudioMetadata(fileURL: sourceURL), let totalFrames = metadata.frameCount, totalFrames > 0 else {
            showError("Could not read metadata or file is empty for \\(sourceURL.lastPathComponent).")
            return
        }

        // Calculate velocity ranges based on the number of segments
        let velocityRanges = calculateSeparateVelocityRanges(numberOfFiles: segments.count)
        guard velocityRanges.count == segments.count else {
            print("ViewModel Error: Mismatch count for velocity ranges when adding segments as layers.")
            showError("Internal error calculating velocity ranges.")
            return
        }

        // --- Prepare New Parts --- 
        var newParts: [MultiSamplePartData] = []
        for (index, segment) in segments.enumerated() {
            let startFrame = Int64(segment.start * Double(totalFrames))
            let endFrame = Int64(segment.end * Double(totalFrames))
            guard startFrame < endFrame, endFrame <= totalFrames else {
                print("ViewModel Warning: Invalid segment frame range [\\(startFrame)-\\(endFrame)] for file \\(sourceURL.lastPathComponent). Skipping segment \\(index).")
                continue
            }
            
            let segmentPart = MultiSamplePartData(
                name: "\\(sourceURL.deletingPathExtension().lastPathComponent)_SegVel\\(index+1)",
                keyRangeMin: midiNote,
                keyRangeMax: midiNote,
                velocityRange: velocityRanges[index], // Assign calculated velocity range
                sourceFileURL: sourceURL,
                segmentStartSample: startFrame,
                segmentEndSample: endFrame,
                relativePath: nil, // Will be set on save
                absolutePath: sourceURL.path,
                originalAbsolutePath: sourceURL.path,
                sampleRate: metadata.sampleRate,
                fileSize: metadata.fileSize,
                crc: nil, // Placeholder
                lastModDate: metadata.lastModDate,
                originalFileFrameCount: totalFrames
            )
            newParts.append(segmentPart)
        }

        // --- Apply changes on Main Thread --- 
        DispatchQueue.main.async {
             self.objectWillChange.send()

             // --- Update Configuration --- 
             // Mapping segments to velocity sets layers = numSegments, RR = 1.
             self.noteLayerConfiguration[midiNote] = segments.count
             self.noteRoundRobinConfiguration[midiNote] = 1
             self.currentMappingMode = .standard // Ensure standard mapping mode
             print("Add Segments as Velocity: Set configuration for note \\(midiNote) to \\(segments.count) layers, 1 RR.")

             // --- Update Sample Parts --- 
             // Clear existing samples for the target note
             let initialCount = self.multiSampleParts.count
             self.multiSampleParts.removeAll { $0.keyRangeMin == midiNote }
             if self.multiSampleParts.count < initialCount {
                  print("ViewModel: Removed \\(initialCount - self.multiSampleParts.count) existing sample(s) for note \\(midiNote).")
             }
             // Add all new parts
             self.multiSampleParts.append(contentsOf: newParts)
             print("ViewModel: Successfully added \\(newParts.count) segments as velocity zones to note \\(midiNote).")
             // The didSet on multiSampleParts will trigger the UI update
         }
    }

    /// Adds multiple sample parts based on segments, mapping them sequentially across MIDI notes.
    /// Updates configuration for each affected note to 1 layer, 1 RR.
    /// Called from AudioSegmentEditorView.
    func autoMapSegmentsSequentially(segments: [(start: Double, end: Double)], startNote: Int, sourceURL: URL) {
        print("ViewModel: Auto-mapping \\(segments.count) segments sequentially from note \\(startNote) using \\(sourceURL.lastPathComponent).")
        guard !segments.isEmpty else { return }

        // Get metadata first
        guard let metadata = extractAudioMetadata(fileURL: sourceURL), let totalFrames = metadata.frameCount, totalFrames > 0 else {
            showError("Could not read metadata or file is empty for \\(sourceURL.lastPathComponent).")
            return
        }

        // --- Determine notes to clear and prepare new parts --- 
        var newParts: [MultiSamplePartData] = []
        var notesToUpdateConfig: Set<Int> = [] // Keep track of notes whose config needs reset

        for (index, segment) in segments.enumerated() {
            let targetNote = startNote + index
            guard targetNote <= 127 else {
                print("ViewModel Warning: Reached max MIDI note (127). Stopping sequential mapping.")
                break // Stop if we exceed MIDI range
            }
            
            notesToUpdateConfig.insert(targetNote)

            let startFrame = Int64(segment.start * Double(totalFrames))
            let endFrame = Int64(segment.end * Double(totalFrames))
            guard startFrame < endFrame, endFrame <= totalFrames else {
                print("ViewModel Warning: Invalid segment [\\(segment.start)-\\(segment.end)] for sequential map. Skipping segment \\(index).")
                continue
            }

            let segmentPart = MultiSamplePartData(
                name: "\\(sourceURL.deletingPathExtension().lastPathComponent)_SeqMap\\(index+1)",
                keyRangeMin: targetNote,
                keyRangeMax: targetNote,
                velocityRange: .fullRange, // Full velocity range for sequential mapping
                sourceFileURL: sourceURL,
                segmentStartSample: startFrame,
                segmentEndSample: endFrame,
                relativePath: nil, // Set on save
                absolutePath: sourceURL.path,
                originalAbsolutePath: sourceURL.path,
                sampleRate: metadata.sampleRate,
                fileSize: metadata.fileSize,
                lastModDate: metadata.lastModDate,
                originalFileFrameCount: totalFrames
            )
            newParts.append(segmentPart)
        }
        
        // --- Apply changes on Main Thread --- 
        DispatchQueue.main.async {
            self.objectWillChange.send() // Important before mutation

            // --- Update Configuration --- 
            // Reset configuration for each affected note to 1 layer, 1 RR.
            for note in notesToUpdateConfig {
                self.noteLayerConfiguration[note] = 1
                self.noteRoundRobinConfiguration[note] = 1
            }
            self.currentMappingMode = .standard // Ensure standard mapping mode
            print("Sequential Map: Reset configuration for \\(notesToUpdateConfig.count) notes to 1 layer, 1 RR.")

            // --- Update Sample Parts --- 
            // Remove existing samples for the notes being mapped
            let initialCount = self.multiSampleParts.count
            self.multiSampleParts.removeAll { $0.keyRangeMin == $0.keyRangeMax && notesToUpdateConfig.contains($0.keyRangeMin) } // Use notesToUpdateConfig here
            if self.multiSampleParts.count < initialCount {
                 print("ViewModel: Removed \\(initialCount - self.multiSampleParts.count) existing sample(s) in target sequential range.")
            }
            // Add the new parts
            self.multiSampleParts.append(contentsOf: newParts)
            print("ViewModel: Successfully auto-mapped \\(newParts.count) segments sequentially starting from note \\(startNote).")
            // didSet will trigger UI update
        }
    }

    // --- NEW: Map Segments as Round Robin from Editor --- // Comment seems old, function exists
    /// Adds multiple sample parts based on segments, mapping them as Round Robin parts on a single note.
    /// Updates configuration to 1 layer, N RRs (N=segments).
    /// Called from AudioSegmentEditorView.
    func mapSegmentsAsRoundRobin(segments: [(start: Double, end: Double)], midiNote: Int, sourceURL: URL, targetLayerIndex: Int) {
        print("ViewModel: Mapping \\(segments.count) segments as Round Robin from \\(sourceURL.lastPathComponent) to note \\(midiNote), target layer index \\(targetLayerIndex).")
        guard !segments.isEmpty else {
            showError("Cannot map: No segments provided.")
            return
        }

        // Get metadata first
        guard let metadata = extractAudioMetadata(fileURL: sourceURL), let totalFrames = metadata.frameCount, totalFrames > 0 else {
            showError("Could not read metadata or file is empty for \\(sourceURL.lastPathComponent). Cannot map Round Robin.")
            return
        }

        // --- Calculate Target Velocity Range --- 
        let numLayers = noteLayerConfiguration[midiNote] ?? 1 // Get current layer count
        guard targetLayerIndex >= 0 && targetLayerIndex < numLayers else {
             print("ViewModel Error: Invalid targetLayerIndex (\\(targetLayerIndex)) for \\(numLayers) configured layers on note \\(midiNote).")
             showError("Cannot map Round Robin: Invalid target layer selected.")
             return
         }
        let layerRanges = calculateSeparateVelocityRanges(numberOfFiles: numLayers)
        guard targetLayerIndex < layerRanges.count else {
             print("ViewModel Error: Could not calculate velocity range for target layer index \\(targetLayerIndex).")
             showError("Internal error calculating velocity range for Round Robin mapping.")
             return
         }
        let targetVelocityRange = layerRanges[targetLayerIndex]
        print("  -> Mapping RR segments to velocity range: [\\(targetVelocityRange.min)-\\(targetVelocityRange.max)]")

        // --- Prepare New Parts --- 
        var newParts: [MultiSamplePartData] = []
        for (index, segment) in segments.enumerated() {
            let startFrame = Int64(segment.start * Double(totalFrames))
            let endFrame = Int64(segment.end * Double(totalFrames))
            guard startFrame < endFrame, endFrame <= totalFrames else {
                print("ViewModel Warning: Invalid segment [\\(segment.start)-\\(segment.end)] for Round Robin map. Skipping segment \\(index).")
                continue
            }

            let segmentPart = MultiSamplePartData(
                name: "\\(sourceURL.deletingPathExtension().lastPathComponent)_RR_Seg\\(index+1)", // Indicate RR + Segment
                keyRangeMin: midiNote,
                keyRangeMax: midiNote,
                velocityRange: targetVelocityRange, // Assign the calculated target layer's velocity range
                sourceFileURL: sourceURL,
                segmentStartSample: startFrame,
                segmentEndSample: endFrame,
                relativePath: nil, // Set on save
                absolutePath: sourceURL.path,
                originalAbsolutePath: sourceURL.path,
                sampleRate: metadata.sampleRate,
                fileSize: metadata.fileSize,
                crc: nil, // Placeholder
                lastModDate: metadata.lastModDate,
                originalFileFrameCount: totalFrames
            )
            newParts.append(segmentPart)
        }
        
        // --- Apply changes on Main Thread --- 
        DispatchQueue.main.async {
            self.objectWillChange.send() // Important before mutation

            // --- Update Configuration --- 
            // Mapping segments to RR sets RR = numSegments for the note.
            // DO NOT reset the number of layers.
            // self.noteLayerConfiguration[midiNote] = 1 // REMOVED - Keep existing layer configuration
            // self.noteRoundRobinConfiguration[midiNote] = segments.count // REMOVED - Will be calculated dynamically
            // --- RESTORE simpler RR config update --- 
            self.noteRoundRobinConfiguration[midiNote] = newParts.count // Set based on number added

            // --- Calculate ANTICIPATED New Max RR Config BEFORE appending ---
            let currentLayers = self.velocityLayers(for: midiNote) // Get current state
            let oldMaxRR = self.noteRoundRobinConfiguration[midiNote] ?? 0
            let samplesInTargetLayer = (targetLayerIndex >= 0 && targetLayerIndex < currentLayers.count) ? currentLayers[targetLayerIndex].activeSampleCount : 0
            let newTargetLayerCount = samplesInTargetLayer + newParts.count
            let newMaxRR = max(oldMaxRR, newTargetLayerCount)

            if newMaxRR != oldMaxRR {
                 print("ViewModel: Anticipating new max RR count of \(newMaxRR) for note \(midiNote) (was \(oldMaxRR)). Updating configuration.")
                 self.objectWillChange.send() // Notify before changing config
                 self.noteRoundRobinConfiguration[midiNote] = newMaxRR
            } else {
                print("ViewModel: Max RR count for note \(midiNote) remains \(oldMaxRR). No configuration change needed.")
            }
            // -----------------------------------------------------------

            // Ensure RR mapping mode for the overall sampler if adding RR parts
            self.currentMappingMode = .roundRobin

            // --- Update Sample Parts ---

            // --- DO NOT REMOVE existing samples ---
            // self.multiSampleParts.removeAll { $0.keyRangeMin == midiNote } // REMOVED

            // Add the new Round Robin parts
            self.multiSampleParts.append(contentsOf: newParts)
            print("ViewModel: Successfully mapped \(newParts.count) segments as Round Robin to note \(midiNote).")

            // Config was updated *before* append, print statement removed from here.

            // didSet will trigger UI update
        }
    }
    // -----------------------------------------------------

    // MARK: - Sample Data Update

    /// Updates the velocity range for a specific sample part identified by its ID within a given MIDI note.
    /// - Parameters:
    ///   - note: The MIDI note number where the sample resides.
    ///   - sampleID: The unique UUID of the MultiSamplePartData to update.
    ///   - newRange: The new VelocityRangeData to apply.
    func updateVelocityRange(note: Int, sampleID: UUID, newRange: VelocityRangeData) {
        print("ViewModel: Request received to update velocity for Sample ID \(sampleID) on Note \(note) to [\(newRange.min)-\(newRange.max)]")

        // Ensure updates happen on the main thread for UI consistency
        DispatchQueue.main.async {
            // Use objectWillChange.send() before mutation for complex updates
            self.objectWillChange.send()

            // Find the index of the sample part to update
            // We need to iterate through the array to find the matching ID.
            // Although we have the 'note', the primary identifier is the UUID.
            if let index = self.multiSampleParts.firstIndex(where: { $0.id == sampleID }) {

                // --- IMPORTANT: Check if the found sample actually belongs to the expected note ---
                // This is a safety check, as IDs should be unique across notes anyway.
                guard self.multiSampleParts[index].keyRangeMin == note else {
                    print("ViewModel ERROR: Found sample ID \(sampleID) at index \(index), but it belongs to note \(self.multiSampleParts[index].keyRangeMin), not the expected note \(note). Aborting update.")
                    // Optionally show an error to the user
                    self.showError("Internal data inconsistency: Sample found but associated with the wrong key.")
                    return
                }

                // --- Update the velocity range ---
                // Since MultiSamplePartData is a struct, modifying it creates a new copy.
                // We need to replace the element in the array with the modified version.
                self.multiSampleParts[index].velocityRange = newRange
                print("ViewModel: Successfully updated velocity range for Sample ID \(sampleID) (Name: \(self.multiSampleParts[index].name)) at index \(index).")

                // The @Published wrapper on multiSampleParts should automatically notify SwiftUI
                // to update any views observing it (like SampleDetailView).
                // The `didSet` on `multiSampleParts` will also trigger `updatePianoKeySampleStatus()`,
                // though that's likely not strictly necessary for just a velocity change.

            } else {
                // Sample ID not found in the array
                print("ViewModel ERROR: Sample ID \(sampleID) not found in multiSampleParts array. Cannot update velocity.")
                // Optionally show an error to the user
                self.showError("Could not find the sample to update its velocity.")
            }
        }
    }

    // MARK: - Error Handling

    /// Shows an error alert to the user.
    func showError(_ message: String) {
        // Ensure UI updates occur on the main thread
        DispatchQueue.main.async {
            self.errorAlertMessage = message
            self.showingErrorAlert = true
             print("Error Alert Presented: \\(message)") // Log for debugging
        }
    }

    // MARK: - New Function: Velocity Layers Data Source

    /// Generates the `VelocityLayer` structure for a given MIDI note,
    /// based on the configuration and existing samples.
    /// This function is intended as the data source for views like SampleDetailView's grid.
    func velocityLayers(for midiNote: Int) -> [VelocityLayer] {
        // 1. Get configuration for the note (use defaults if not set)
        // Default to 1 layer and 1 RR slot if no specific configuration exists for this note.
        let numLayers = noteLayerConfiguration[midiNote] ?? 1
        let maxRR = noteRoundRobinConfiguration[midiNote] ?? 1

        print("Generating layers for note \\(midiNote): \\(numLayers) layers, \\(maxRR) max RRs per layer.")

        // 2. Calculate velocity ranges for the layers
        // Reusing the existing logic for calculating separate (non-overlapping) ranges.
        let layerRanges = calculateSeparateVelocityRanges(numberOfFiles: numLayers)

        // Ensure ranges were calculated correctly
        guard layerRanges.count == numLayers else {
            print("Error generating layers for note \\(midiNote): Mismatch in calculated ranges (\(layerRanges.count)) vs expected (\(numLayers)). Returning empty.")
            // Consider showing an error or returning a default single layer.
            return []
        }
        print("  -> Calculated \\(layerRanges.count) velocity ranges.")

        // 3. Create the basic layer structure with empty RR slots
        var resultLayers: [VelocityLayer] = []
        for range in layerRanges {
            // Create a layer with the calculated range and an array of `nil`s for RR slots.
            // Each `nil` represents an empty Round Robin slot within this velocity layer.
            let layer = VelocityLayer(velocityRange: range, samples: Array(repeating: nil, count: maxRR))
            resultLayers.append(layer)
        }
         print("  -> Created \\(resultLayers.count) initial VelocityLayer structs with \\(maxRR) RR slots each.")

        // 4. Filter existing samples (`MultiSamplePartData`) that belong to this MIDI note
        let partsForNote = multiSampleParts.filter { $0.keyRangeMin == midiNote }
         print("  -> Found \\(partsForNote.count) existing MultiSamplePartData items for note \\(midiNote).")

        // 5. Place existing samples into the correct layer/RR slot based on their velocity
        for part in partsForNote {
            // Find the layer this part belongs to based on its minimum velocity.
            // It fits if the part's min velocity falls within the layer's min/max range.
            if let layerIndex = resultLayers.firstIndex(where: { $0.velocityRange.min <= part.velocityRange.min && $0.velocityRange.max >= part.velocityRange.min }) {
                 print("    -> Part \\(part.name) (Vel: \\(part.velocityRange.min)-\\(part.velocityRange.max)) fits into Layer \\(layerIndex) (Range: \\(resultLayers[layerIndex].velocityRange.min)-\\(resultLayers[layerIndex].velocityRange.max))")

                // Find the first empty (nil) Round Robin slot in that layer
                if let rrIndex = resultLayers[layerIndex].samples.firstIndex(where: { $0 == nil }) {
                    // Place the sample data into the slot
                    resultLayers[layerIndex].samples[rrIndex] = part
                     print("      -> Placed into RR slot \\(rrIndex).")
                } else {
                    // Handle the case where the layer is full (no more nil slots)
                    print("    -> Warning: Note \\(midiNote), Layer \\(layerIndex) (\(resultLayers[layerIndex].velocityRange.min)-\\(resultLayers[layerIndex].velocityRange.max)): No more RR slots available for sample \\(part.name). Max RR: \\(maxRR). Sample *not* placed in this layer.")
                    // Potential handling strategies for overflow:
                    // 1. Discard: The sample is ignored (current behavior).
                    // 2. Append: Dynamically increase the size of the `samples` array in `VelocityLayer` (requires `samples` to be `var`).
                    // 3. Replace: Overwrite the last sample in the layer.
                    // 4. Error: Show an error to the user.
                }
            } else {
                 // Handle the case where the sample's velocity doesn't fit any defined layer
                 print("    -> Warning: Note \\(midiNote): Sample \\(part.name) with range \\(part.velocityRange.min)-\\(part.velocityRange.max) does not fit into any of the \\(numLayers) defined velocity layer ranges. Sample *not* placed.")
                 // This might happen if sample velocity ranges were set independently
                 // before the layer configuration was established or changed.
            }
        } // End of loop through partsForNote

        print("  -> Finished placing existing samples. Returning \\(resultLayers.count) layers for note \\(midiNote).")
        return resultLayers
    }

    // MARK: - Grid Interaction Logic

    /// Adds a sample to a specific layer/RR slot, forcing its velocity to match the layer.
    func addSampleToGridSlot(partData: MultiSamplePartData, layerIndex: Int, rrIndex: Int, forNote midiNote: Int) {
        print("ViewModel: Adding sample \\(partData.name) to Note \\(midiNote), Layer \\(layerIndex), RR \\(rrIndex)")
        
        // 1. Get Layer Configuration
        let numLayers = noteLayerConfiguration[midiNote] ?? 1
        guard layerIndex < numLayers else {
            print("Error: Attempted to add to layer index \\(layerIndex) but only \\(numLayers) are configured for note \\(midiNote).")
            showError("Cannot add sample: Target layer index is out of bounds.")
            return
        }

        // 2. Calculate the target layer's velocity range
        let layerRanges = calculateSeparateVelocityRanges(numberOfFiles: numLayers)
        guard layerIndex < layerRanges.count else {
             print("Error: Could not calculate velocity range for layer index \\(layerIndex) (numLayers: \\(numLayers)).")
             showError("Internal error calculating velocity range.")
             return
         }
        let targetVelocityRange = layerRanges[layerIndex]
        print("  -> Target Layer \\(layerIndex) Velocity Range: [\\(targetVelocityRange.min)-\\(targetVelocityRange.max)]")

        // 3. Create the final MultiSamplePartData with the FORCED velocity range
        // We create a new instance based on the input, only changing the velocity.
        let finalPartData = MultiSamplePartData(
            name: partData.name,
            keyRangeMin: midiNote, // Ensure it's assigned to the correct note
            keyRangeMax: midiNote,
            velocityRange: targetVelocityRange, // FORCE the velocity range
            sourceFileURL: partData.sourceFileURL,
            segmentStartSample: partData.segmentStartSample,
            segmentEndSample: partData.segmentEndSample,
            relativePath: partData.relativePath,
            absolutePath: partData.absolutePath,
            originalAbsolutePath: partData.originalAbsolutePath,
            sampleRate: partData.sampleRate,
            fileSize: partData.fileSize,
            crc: partData.crc,
            lastModDate: partData.lastModDate,
            originalFileFrameCount: partData.originalFileFrameCount
            // Retain other properties from the input partData
        )

        // 4. Add to the main data store (Main Thread)
        DispatchQueue.main.async {
            self.objectWillChange.send()
            
            // --- TODO: Overwrite/Replace Logic (Phase 1: Simple Append) --- 
            // For now, we just append. The velocityLayers(for:) function will place it.
            // Later, we might want logic here to find if a sample *already* exists
            // specifically intended for this layerIndex/rrIndex based on some criteria 
            // (maybe storing layer/rr indices *in* MultiSamplePartData?), and remove it first.
            // For now, relying on velocityLayers(for:) to sort it out is simpler.
            self.multiSampleParts.append(finalPartData)
            print("  -> Appended \\(finalPartData.name) to multiSampleParts.")
            
            // Optional: Check if this addition exceeds configured RRs and inform user?
            let maxRR = self.noteRoundRobinConfiguration[midiNote] ?? 1
            let currentSamplesInLayer = self.velocityLayers(for: midiNote)[layerIndex].activeSampleCount
            if currentSamplesInLayer > maxRR { // Check *after* adding conceptually
                 print("  -> Warning: Layer \\(layerIndex) now has \\(currentSamplesInLayer) samples, exceeding configured max RRs (\\(maxRR)).")
                 // Optionally show a non-blocking notification?
            }
            
            // The updatePianoKeySampleStatus() will be called via the didSet of multiSampleParts.
        }
    }
    
    /// Removes a sample from a specific layer/RR slot.
    func removeSampleFromGridSlot(layerId: UUID, rrIndex: Int, forNote midiNote: Int) {
        print("ViewModel: Removing sample from Note \\(midiNote), Layer ID \\(layerId), RR Index \\(rrIndex)")

        // 1. Regenerate the layer structure to find the sample ID
        // This is slightly inefficient but ensures we use the same logic as the view.
        let currentLayers = velocityLayers(for: midiNote)
        
        // 2. Find the target layer using its ID
        guard let layerIndex = currentLayers.firstIndex(where: { $0.id == layerId }) else {
            print("Error: Could not find layer with ID \\(layerId) for note \\(midiNote).")
            showError("Could not find the specified layer to remove the sample from.")
            return
        }

        let targetLayer = currentLayers[layerIndex]

        // 3. Validate the RR index and get the sample data
        guard rrIndex >= 0 && rrIndex < targetLayer.samples.count else {
             print("Error: RR index \\(rrIndex) is out of bounds for layer \\(layerId) (sample count: \\(targetLayer.samples.count)).")
             showError("Invalid sample slot index provided for removal.")
             return
        }

        guard let sampleToRemove = targetLayer.samples[rrIndex] else {
            print("Warning: No sample found at Layer ID \\(layerId), RR Index \\(rrIndex). Nothing to remove.")
            // No error needed, just means the slot was already empty.
            return
        }

        let sampleIdToRemove = sampleToRemove.id
        print("  -> Found sample to remove: ID \\(sampleIdToRemove), Name: \\(sampleToRemove.name)")

        // 4. Remove from the main data store (Main Thread)
        DispatchQueue.main.async {
            self.objectWillChange.send()
            
            let initialCount = self.multiSampleParts.count
            self.multiSampleParts.removeAll { $0.id == sampleIdToRemove }
            let finalCount = self.multiSampleParts.count

            if finalCount < initialCount {
                print("  -> Successfully removed sample with ID \\(sampleIdToRemove) from multiSampleParts.")
            } else {
                 print("  -> Warning: Sample ID \\(sampleIdToRemove) was not found in multiSampleParts array during removal attempt.")
                 // This might indicate a logic inconsistency.
            }
            // The updatePianoKeySampleStatus() will be called via the didSet of multiSampleParts.
        }
    }
}

// MARK: - String Extension for XML Cleaning

extension String {
    /// Cleans a string for safe inclusion in XML attributes or elements
    /// by escaping predefined entities.
    func cleanedForXml() -> String {
        var cleaned = self // Create mutable copy
        // Order matters: & must be escaped first
        cleaned = cleaned.replacingOccurrences(of: "&", with: "&amp;")
        cleaned = cleaned.replacingOccurrences(of: "<", with: "&lt;")
        cleaned = cleaned.replacingOccurrences(of: ">", with: "&gt;")
        cleaned = cleaned.replacingOccurrences(of: "\"", with: "&quot;")
        cleaned = cleaned.replacingOccurrences(of: "'", with: "&apos;")
        // Add any other necessary replacements here (e.g., control characters if needed)
        return cleaned
    }
}

// We no longer need the macOS-specific handleDrop extension here,
// as drop handling is now managed within the SwiftUI views.
// #if os(macOS)
// extension SamplerViewModel { ... }
// #endif
