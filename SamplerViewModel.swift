// File: AbletonSampler/AbletonSampler/SamplerViewModel.swift
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers // Needed for UTType
import Foundation // Needed for Process, Pipe, FileManager, URL
import AudioKit

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
    var min: Int // Changed from let
    var max: Int // Changed from let
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
    var keyRangeMin: Int // Changed from let - MIDI note number
    var keyRangeMax: Int // Changed from let - MIDI note number (same as min for single key mapping)
    var velocityRange: VelocityRangeData
    let sourceFileURL: URL // Original URL of the audio file containing the segment
    var segmentStartSample: Int64 // Start frame within the source file
    var segmentEndSample: Int64 // End frame (exclusive) within the source file. Must be provided.
    var roundRobinIndex: Int? // NEW: Optional index for round robin playback

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

    // --- State (Internal) ---
    @Published private var waveformCache: [URL: [Float]] = [:]

    // --- Initialization ---

    init() {
        print("SamplerViewModel initialized.")
        // Keep cache clear for testing
        self.waveformCache = [:] 
        print("Waveform cache cleared.")
        self.pianoKeys = generatePianoKeys()
        updatePianoKeySampleStatus()
        print("Initialized \(pianoKeys.count) piano keys.")
    }

    // MARK: - Piano Key State Update (NEW)

    /// Updates the `hasSample` property for each key in `pianoKeys`
    /// based on the current contents of `multiSampleParts`.
    private func updatePianoKeySampleStatus() {
         // Use a Set for efficient lookup of mapped MIDI notes
         let mappedNotes = Set(multiSampleParts.map { $0.keyRangeMin })

         print("Updating piano key sample status. Mapped notes: \(mappedNotes)")

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
                 print(" -> Key \(keyMidiNote) ('\(updatedKeys[i].name)') status changed to \(shouldHaveSample)")
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
    private func processSingleFileDrop(midiNote: Int, fileURL: URL) {
        guard let metadata = extractAudioMetadata(fileURL: fileURL) else {
            showError("Could not read metadata for \(fileURL.lastPathComponent).")
            return
        }

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

        // Add the new part to our main data array
        // Ensure UI updates on the main thread
        DispatchQueue.main.async {
            // Using objectWillChange manually before appending is good practice
            // if complex updates might not be automatically detected.
            self.objectWillChange.send()
            // Remove any existing parts for this key before adding the new one
            self.multiSampleParts.removeAll { $0.keyRangeMin == midiNote }
            self.multiSampleParts.append(partData)
            // `multiSampleParts` didSet will trigger updatePianoKeySampleStatus()
            print("Added single sample part: \(partData.name) to key \(midiNote)")
        }
    }


    /// Processes multiple dropped files based on the user's chosen velocity split mode.
    /// This function is called after the user interacts with the velocity split prompt.
    /// - Parameter mode: The `VelocitySplitMode` selected by the user (.separate or .crossfade).
    func processMultiDrop(mode: VelocitySplitMode) {
        print("Processing multi-drop with mode: \(mode)")
        guard let info = pendingDropInfo else {
            print("Error: No pending drop info found.")
            // Clear the prompt state just in case
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

        // Calculate the velocity ranges based on the chosen mode
        let velocityRanges = calculateVelocityRanges(numberOfFiles: numberOfFiles, mode: mode)

        // Ensure we got the correct number of ranges
        guard velocityRanges.count == numberOfFiles else {
            print("Error: Mismatch between number of files (\(numberOfFiles)) and calculated velocity ranges (\(velocityRanges.count)).")
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
                print("Warning: Could not read metadata for \(fileURL.lastPathComponent). Skipping this file.")
                // Optionally inform the user about skipped files
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
            print("Prepared multi-sample part \(index + 1)/\(numberOfFiles): \(partData.name) for key \(midiNote) with vel range [\(partData.velocityRange.min)-\(partData.velocityRange.max)]")
        }

        // Add the new parts to the main data array and clear pending state
        // Ensure UI updates on the main thread
        DispatchQueue.main.async {
            // Use objectWillChange for clarity
            self.objectWillChange.send()
             // Remove any existing parts for this key before adding the new ones
            self.multiSampleParts.removeAll { $0.keyRangeMin == midiNote }
            self.multiSampleParts.append(contentsOf: newParts)
            self.pendingDropInfo = nil
            self.showingVelocitySplitPrompt = false
            // `multiSampleParts` didSet will trigger updatePianoKeySampleStatus()
            print("Finished processing multi-drop. Added \(newParts.count) parts.")
        }
    }

    /// Processes multiple dropped files as Round Robin samples on a single key.
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

        // --- Prepare Parts (no velocity calc needed) --- 
        var newPartsData: [MultiSamplePartData] = []
        for (index, fileURL) in fileURLs.enumerated() {
            guard let metadata = extractAudioMetadata(fileURL: fileURL) else {
                print("Warning: Could not read metadata for \(fileURL.lastPathComponent). Skipping this file for Round Robin.")
                continue // Skip this file
            }

            let partData = MultiSamplePartData(
                name: fileURL.deletingPathExtension().lastPathComponent + "_RR_\(index + 1)", // Add RR suffix
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
            print("Prepared RR part \(index + 1)/\(numberOfFiles): \(partData.name) for key \(midiNote)")
        }

        // --- Add Parts and Update State --- 
        DispatchQueue.main.async {
            self.objectWillChange.send()
            // First, clear *all* existing parts for the target note before adding RR samples.
            // This prevents mixing velocity-split and RR samples on the same key.
            print("Clearing existing parts on note \(midiNote) before adding Round Robin samples.")
            var partsRemoved = false
            let initialCount = self.multiSampleParts.count
            self.multiSampleParts.removeAll { $0.keyRangeMin == midiNote }
            if self.multiSampleParts.count != initialCount {
                partsRemoved = true
            }


            // Add the new Round Robin parts
            // We are appending directly here for simplicity since addSampleSegment might have complex interactions
            // we don't need when just adding RR parts after a clear.
            self.multiSampleParts.append(contentsOf: newPartsData)


            // Set the global mapping mode
            self.currentMappingMode = .roundRobin
            print("Set mapping mode to Round Robin.")

            // Clear pending info and hide prompt
            self.pendingDropInfo = nil
            self.showingVelocitySplitPrompt = false

            // Explicitly trigger update if parts were removed but none added, or if parts were added.
            // The didSet on multiSampleParts handles the update, but logging completion here.
             print("Finished processing multi-drop for Round Robin. Added \(newPartsData.count) parts.")
             // If parts were only removed, the didSet might not have triggered if newPartsData was empty.
             // Calling update explicitly ensures correctness in that edge case.
             if partsRemoved && newPartsData.isEmpty {
                 self.updatePianoKeySampleStatus()
             }
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
    private struct AudioMetadata {
        let sampleRate: Double?
        let frameCount: Int64?
        let fileSize: Int64?
        let lastModDate: Date?
        // Add CRC later if needed
    }

    /// Extracts relevant metadata from an audio file URL.
    /// - Parameter fileURL: The URL of the audio file.
    /// - Returns: An optional `AudioMetadata` struct, or nil if extraction fails.
    private func extractAudioMetadata(fileURL: URL) -> AudioMetadata? {
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


    // MARK: - Waveform Data Extraction & Caching (REVERTED)
    /// Asynchronously retrieves or calculates RMS waveform data for display.
    /// Uses a cache to avoid redundant calculations.
    /// - Parameter fileURL: The URL of the audio file.
    /// - Returns: An optional array of Float values representing RMS data, or nil on failure.
    @MainActor
    func getWaveformRMSData(for fileURL: URL) async -> [Float]? { // REVERTED Return Type
        // 1. Check Cache
        if let cachedData = waveformCache[fileURL] { // REVERTED Cache Check
            print("Waveform Cache HIT for: \(fileURL.lastPathComponent)")
            return cachedData
        }
        
        print("Waveform Cache MISS for: \(fileURL.lastPathComponent). Calculating...")
        let securityScoped = fileURL.startAccessingSecurityScopedResource()
        defer { if securityScoped { fileURL.stopAccessingSecurityScopedResource() } }
        
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let frameCount = audioFile.length
            guard frameCount > 0 else { return nil }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
            try audioFile.read(into: buffer)

            // --- Calculate RMS Samples (REVERTED to fixed samplesPerPixel) ---
            let samplesPerPixel = 1024 // Reverted to original value
            let displaySamplesCount = max(1, Int(frameCount) / samplesPerPixel)
            print("  -> Using fixed samplesPerPixel: \(samplesPerPixel), Actual RMS Samples: \(displaySamplesCount)")
            var rmsSamples = [Float](repeating: 0.0, count: displaySamplesCount)
            guard let floatChannelData = buffer.floatChannelData else { return nil }
            let channelData = floatChannelData[0]

            for i in 0..<displaySamplesCount {
                let startSample = i * samplesPerPixel
                let endSample = min(startSample + samplesPerPixel, Int(frameCount))
                let blockSampleCount = endSample - startSample
                if blockSampleCount > 0 {
                    var sumOfSquares: Float = 0.0
                    for j in startSample..<endSample { sumOfSquares += channelData[j] * channelData[j] }
                    rmsSamples[i] = sqrt(sumOfSquares / Float(blockSampleCount))
                } else { rmsSamples[i] = 0.0 }
            }
            // -----------------------------------------------------------------
            
            print("  -> Waveform calculation successful. Display samples: \(rmsSamples.count)")
            
            // Store [Float] in cache
            waveformCache[fileURL] = rmsSamples
            return rmsSamples // Return [Float]?

        } catch {
            print("  -> Error calculating waveform for \(fileURL.lastPathComponent): \(error)")
            return nil
        }
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


    // MARK: - Sample Part Management (CRUD Operations)

    /// Adds multiple `MultiSamplePartData` objects to the main array.
    /// Ensures the update happens on the main thread.
    func addMultiSampleParts(_ partsToAdd: [MultiSamplePartData]) {
        DispatchQueue.main.async {
            // Using objectWillChange manually before appending can be slightly safer
            // if updates are complex, though didSet should handle this.
            self.objectWillChange.send()
            self.multiSampleParts.append(contentsOf: partsToAdd)
            print("Added \(partsToAdd.count) new sample parts.")
            // updatePianoKeySampleStatus() is called automatically by didSet
        }
    }

    /// Removes a sample part by its ID.
    func removeMultiSamplePart(id: UUID) {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            let initialCount = self.multiSampleParts.count
            self.multiSampleParts.removeAll { $0.id == id }
            if self.multiSampleParts.count < initialCount {
                print("Removed sample part with ID: \(id)")
            } else {
                print("Could not remove sample part: ID \(id) not found.")
            }
        }
    }

    // --- Update a specific MultiSamplePartData (e.g., for segment marker dragging) ---
    func updateMultiSamplePart(_ updatedPartData: MultiSamplePartData) {
         DispatchQueue.main.async { // Ensure updates happen on the main thread
             if let index = self.multiSampleParts.firstIndex(where: { $0.id == updatedPartData.id }) {
                 // Perform validation before updating
                 guard let totalFrames = updatedPartData.originalFileFrameCount, totalFrames > 0 else {
                     print("Error updating part \(updatedPartData.id): Original frame count missing or invalid.")
                     self.showError("Cannot update sample part: Original file length information is missing.")
                     return
                 }

                 // Validate and clamp segment boundaries
                 let validatedStartSample = max(0, min(updatedPartData.segmentStartSample, totalFrames - 1))
                 let validatedEndSample = max(validatedStartSample + 1, min(updatedPartData.segmentEndSample, totalFrames)) // Ensure end > start and <= totalFrames

                 // Create the final validated part to store
                 var finalPart = updatedPartData
                 finalPart.segmentStartSample = validatedStartSample
                 finalPart.segmentEndSample = validatedEndSample

                 // Validate velocity range
                 finalPart.velocityRange.min = max(0, min(updatedPartData.velocityRange.min, 127))
                 finalPart.velocityRange.max = max(finalPart.velocityRange.min, min(updatedPartData.velocityRange.max, 127))
                 // TODO: Add validation for velocity crossfade values if they become editable

                 // Validate Note Number
                 finalPart.keyRangeMin = max(0, min(updatedPartData.keyRangeMin, 127))
                 finalPart.keyRangeMax = finalPart.keyRangeMin // Keep min/max the same for single note mapping

                 // Update the array
                 self.multiSampleParts[index] = finalPart
                 print("Updated MultiSamplePartData for ID: \(updatedPartData.id)")
                 // No need to manually call updatePianoKeySampleStatus, didSet on multiSampleParts handles it.
             } else {
                 print("Error updating part: Could not find MultiSamplePartData with ID: \(updatedPartData.id)")
                 // Optionally show an error to the user
                 // self.showError("Failed to save changes: Sample part not found.")
             }
         }
     }


    /// Updates only the segment start or end sample for a specific MultiSamplePartData.
     /// Ensures that start < end and both are within the original file bounds [0, originalFileFrameCount).
     /// - Parameters:
     ///   - partID: The UUID of the `MultiSamplePartData` to update.
     ///   - newStartSample: The proposed new start sample frame. If nil, the start sample is not changed.
     ///   - newEndSample: The proposed new end sample frame. If nil, the end sample is not changed.
     func updateSegmentBoundary(partID: UUID, newStartSample: Int64?, newEndSample: Int64?) {
         DispatchQueue.main.async {
             guard let index = self.multiSampleParts.firstIndex(where: { $0.id == partID }) else {
                 print("Error updating segment boundary: Part ID \(partID) not found.")
                 // self.showError("Could not update segment: Sample part not found.")
                 return
             }

             var partToUpdate = self.multiSampleParts[index]

             // Ensure original file frame count is available
             guard let totalFrames = partToUpdate.originalFileFrameCount, totalFrames > 0 else {
                 print("Error updating segment boundary for \(partID): Original frame count missing.")
                 self.showError("Cannot update segment boundaries: Original file length information is missing.")
                 return
             }

             // Get current values
             var currentStart = partToUpdate.segmentStartSample
             var currentEnd = partToUpdate.segmentEndSample

             // --- Update Start Sample ---
             if let proposedStart = newStartSample {
                 // Clamp proposed start: 0 <= proposedStart < totalFrames
                 let clampedStart = max(0, min(proposedStart, totalFrames - 1))
                 // Ensure start doesn't go past the *current* end (minus 1 frame minimum length)
                 currentStart = min(clampedStart, currentEnd - 1)
                 // Ensure start is still non-negative after potentially being limited by end
                 currentStart = max(0, currentStart)
                 print("Updating Start Sample for \(partID): Proposed=\(proposedStart), Clamped=\(clampedStart), Final=\(currentStart)")
             }

             // --- Update End Sample ---
             if let proposedEnd = newEndSample {
                 // Clamp proposed end: 0 < proposedEnd <= totalFrames
                 // Note: End sample is often treated as *exclusive* in ranges, but here it seems *inclusive* based on XML/Ableton?
                 // Let's assume it marks the *last* sample frame to include. So max value is totalFrames - 1?
                 // NO - Ableton ADV XML uses <SampleEnd Value="X"/> which seems to be the frame *after* the last sample.
                 // Let's stick to: End sample MUST be > Start Sample and End Sample <= totalFrames
                 let clampedEnd = max(1, min(proposedEnd, totalFrames)) // Clamp: 1 <= proposedEnd <= totalFrames
                 // Ensure end doesn't go below the *updated* start (plus 1 frame minimum length)
                 currentEnd = max(currentStart + 1, clampedEnd)
                 // Ensure end doesn't exceed total frames
                 currentEnd = min(currentEnd, totalFrames)
                 print("Updating End Sample for \(partID): Proposed=\(proposedEnd), Clamped=\(clampedEnd), Final=\(currentEnd)")
             }

             // --- Final Validation ---
             // Double-check if start somehow ended up >= end after individual updates
             if currentStart >= currentEnd {
                 print("Error updating segment boundary for \(partID): Invalid final state (Start=\(currentStart), End=\(currentEnd)). Reverting to previous state.")
                 // Optionally revert or adjust automatically, for now just log and don't update.
                 // self.showError("Failed to update segment boundaries due to invalid range.") // Maybe too noisy?
                 return
             }

             // Apply the validated updates
             self.multiSampleParts[index].segmentStartSample = currentStart
             self.multiSampleParts[index].segmentEndSample = currentEnd

             print("Successfully updated segment boundaries for \(partID): Start=\(currentStart), End=\(currentEnd)")
             // No need to call updatePianoKeySampleStatus, didSet handles it.
         }
     }

    // MARK: - Transient Detection (REVERTED - Modified Normalization)

    /// Detects transients in waveform RMS data.
    /// - Parameters:
    ///   - rmsData: An array of pre-calculated RMS or amplitude values.
    ///   - threshold: Sensitivity threshold (0.0 to 1.0). Lower value = more sensitive.
    ///   - totalFrames: The total number of frames in the original audio file (Used for clamping final calculation if needed, but primary calculation uses RMS count).
    /// - Returns: An array of normalized positions (`Double` from 0.0 to 1.0) where transients were detected.
    /// - Throws: Potential calculation errors.
    func detectTransients(rmsData: [Float], threshold: Float, totalFrames: Int64) throws -> [Double] { // Corrected Signature
        // --- START Function Body Correction ---
        guard !rmsData.isEmpty else {
            print("Transient Detection: RMS data is empty.")
            return []
        }
         // samplesPerPixel is no longer used
         // Keep guard totalFrames > 0 for potential future use or validation.
         guard totalFrames > 0 else {
             throw NSError(domain: "SamplerViewModelError", code: 5, userInfo: [NSLocalizedDescriptionKey: "totalFrames must be positive for context."])
         }

        let dataCount = rmsData.count
        guard dataCount > 1 else { return [] }

        var transientPositions: [Double] = [] // Store normalized positions
        let minEnergyThreshold: Float = 0.005
        let debounceSamples: Int = 2 // Debounce based on RMS sample indices
        var lastTransientRMSIndex: Int = -debounceSamples // Use correct initial value

        // Calculate differences between consecutive RMS values
        var differences: [Float] = []
        for i in 0..<(dataCount - 1) { differences.append(abs(rmsData[i+1] - rmsData[i])) }
        guard let maxDifference = differences.max(), maxDifference > 0 else { return [] }

        // Look for peaks in the differences
        for i in 0..<differences.count { // i is the index *before* the potential peak at i+1
             let normalizedDiff = differences[i] / maxDifference
             let peakRMSIndex = i + 1 // The actual peak is at this RMS index

             // Check threshold, minimum energy, and debounce
             // Use peakRMSIndex for debounce comparison
             if normalizedDiff > threshold && rmsData[peakRMSIndex] > minEnergyThreshold && peakRMSIndex > (lastTransientRMSIndex + debounceSamples) {
                 // --- Calculate Normalized Position directly from RMS index --- 
                 let normalizedPosition = Double(peakRMSIndex) / Double(dataCount - 1)
                 // --- END CALCULATION ---

                 // Clamp normalized position [0.0, 1.0]
                 let clampedPosition = max(0.0, min(1.0, normalizedPosition))

                 transientPositions.append(clampedPosition) // Append normalized position
                 print("  -> Transient Candidate: RMS index=\(peakRMSIndex), NormPos=\(String(format: "%.4f", clampedPosition))")
                 lastTransientRMSIndex = peakRMSIndex // Update debounce index
             }
         }

        print("Transient Detection Complete: Found \(transientPositions.count) transients (normalized positions).")
        return transientPositions.sorted() // Return sorted [Double]
        // --- END Function Body Correction ---
    }

    // MARK: - Error Handling

    /// Shows an error alert to the user.
    func showError(_ message: String) {
        // Ensure UI updates occur on the main thread
        DispatchQueue.main.async {
            self.errorAlertMessage = message
            self.showingErrorAlert = true
             print("Error Alert Presented: \(message)") // Log for debugging
        }
    }

    /// Clears the current error state.
    func clearError() {
        DispatchQueue.main.async {
            self.errorAlertMessage = nil
            self.showingErrorAlert = false
            print("Error Alert Cleared.")
        }
    }

    // MARK: - Helper Functions

    /// Converts a MIDI note number (0-127) to its standard name (e.g., "C4", "F#3").
    static func noteNumberToName(_ noteNumber: Int) -> String {
        guard (0...127).contains(noteNumber) else {
            return "Invalid"
        }
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let keyIndexInOctave = noteNumber % 12
        let noteName = noteNames[keyIndexInOctave]
        let actualOctave = (noteNumber / 12) - 2
        return "\(noteName)\(actualOctave)"
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
