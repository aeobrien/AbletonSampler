import Foundation

/// Represents the parsed components from a sample filename
struct ParsedSampleInfo {
    let originalFileName: String
    let sampleName: String
    let midiNote: Int?
    let velocityRange: (min: Int, max: Int)?
    let roundRobinIndex: Int?
    
    /// Returns a human-readable description of the parsed info
    var description: String {
        var parts = [sampleName]
        if let note = midiNote {
            parts.append("Note: \(note)")
        }
        if let vel = velocityRange {
            parts.append("Vel: \(vel.min)-\(vel.max)")
        }
        if let rr = roundRobinIndex {
            parts.append("RR: \(rr)")
        }
        return parts.joined(separator: ", ")
    }
}

/// Utility class for parsing sample filenames according to various naming conventions
class FileNameParser {
    
    // MARK: - Note Name to MIDI Conversion
    
    /// Convert note name (e.g., "C3", "F#4") to MIDI note number
    private static func noteNameToMidi(_ noteName: String) -> Int? {
        // Clean the input
        let cleaned = noteName.trimmingCharacters(in: .whitespaces).uppercased()
        
        // Match pattern like C3, F#4, Bb2, etc.
        let pattern = #"^([A-G])([#B]?)(-?\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) else {
            return nil
        }
        
        // Extract components
        guard let noteRange = Range(match.range(at: 1), in: cleaned),
              let octaveRange = Range(match.range(at: 3), in: cleaned) else {
            return nil
        }
        
        let note = String(cleaned[noteRange])
        let accidental = match.range(at: 2).length > 0 ? 
            (Range(match.range(at: 2), in: cleaned).map { String(cleaned[$0]) } ?? "") : ""
        let octaveStr = String(cleaned[octaveRange])
        
        guard let octave = Int(octaveStr) else { return nil }
        
        // Base MIDI values for notes (C = 0)
        let noteValues: [String: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
        ]
        
        guard let baseNote = noteValues[note] else { return nil }
        
        // Adjust for accidentals
        let accidentalAdjust = accidental == "#" ? 1 : (accidental == "B" ? -1 : 0)
        
        // Calculate MIDI note (C4 = 60, so octave 4 starts at 60 - 0 = 60)
        // Some DAWs use C3 = 60, others use C4 = 60. We'll use C3 = 60 (Ableton convention)
        let midiNote = (octave + 2) * 12 + baseNote + accidentalAdjust
        
        // Ensure valid MIDI range
        return (0...127).contains(midiNote) ? midiNote : nil
    }
    
    // MARK: - Parsing Methods
    
    /// Main parsing function that tries various patterns
    static func parse(fileName: String) -> ParsedSampleInfo {
        // Remove file extension
        let nameWithoutExt = (fileName as NSString).deletingPathExtension
        
        // Try patterns in order of specificity
        if let result = parseFullPattern(nameWithoutExt) {
            return result
        }
        
        if let result = parseNoteVelocityPattern(nameWithoutExt) {
            return result
        }
        
        if let result = parseNoteRoundRobinPattern(nameWithoutExt) {
            return result
        }
        
        if let result = parseNoteOnlyPattern(nameWithoutExt) {
            return result
        }
        
        // No pattern matched - return just the name
        return ParsedSampleInfo(
            originalFileName: fileName,
            sampleName: nameWithoutExt,
            midiNote: nil,
            velocityRange: nil,
            roundRobinIndex: nil
        )
    }
    
    /// Parse pattern: SampleName_C3_v0-20_rr1
    private static func parseFullPattern(_ name: String) -> ParsedSampleInfo? {
        let pattern = #"^(.+?)_([A-G][#B]?-?\d+|\d{1,3})_v(\d+)[_-](\d+)_rr(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else {
            return nil
        }
        
        guard let sampleNameRange = Range(match.range(at: 1), in: name),
              let noteRange = Range(match.range(at: 2), in: name),
              let velMinRange = Range(match.range(at: 3), in: name),
              let velMaxRange = Range(match.range(at: 4), in: name),
              let rrRange = Range(match.range(at: 5), in: name) else {
            return nil
        }
        
        let sampleName = String(name[sampleNameRange])
        let noteStr = String(name[noteRange])
        let velMinStr = String(name[velMinRange])
        let velMaxStr = String(name[velMaxRange])
        let rrStr = String(name[rrRange])
        
        // Parse note (could be note name or MIDI number)
        let midiNote = Int(noteStr) ?? noteNameToMidi(noteStr)
        
        guard let velMin = Int(velMinStr),
              let velMax = Int(velMaxStr),
              let rr = Int(rrStr) else {
            return nil
        }
        
        return ParsedSampleInfo(
            originalFileName: name,
            sampleName: sampleName,
            midiNote: midiNote,
            velocityRange: (min: velMin, max: velMax),
            roundRobinIndex: rr
        )
    }
    
    /// Parse pattern: SampleName_C3_v0-20 or SampleName_48_v0-20
    private static func parseNoteVelocityPattern(_ name: String) -> ParsedSampleInfo? {
        let pattern = #"^(.+?)_([A-G][#B]?-?\d+|\d{1,3})_v(\d+)[_-](\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else {
            return nil
        }
        
        guard let sampleNameRange = Range(match.range(at: 1), in: name),
              let noteRange = Range(match.range(at: 2), in: name),
              let velMinRange = Range(match.range(at: 3), in: name),
              let velMaxRange = Range(match.range(at: 4), in: name) else {
            return nil
        }
        
        let sampleName = String(name[sampleNameRange])
        let noteStr = String(name[noteRange])
        let velMinStr = String(name[velMinRange])
        let velMaxStr = String(name[velMaxRange])
        
        let midiNote = Int(noteStr) ?? noteNameToMidi(noteStr)
        
        guard let velMin = Int(velMinStr),
              let velMax = Int(velMaxStr) else {
            return nil
        }
        
        return ParsedSampleInfo(
            originalFileName: name,
            sampleName: sampleName,
            midiNote: midiNote,
            velocityRange: (min: velMin, max: velMax),
            roundRobinIndex: nil
        )
    }
    
    /// Parse pattern: SampleName_C3_rr2
    private static func parseNoteRoundRobinPattern(_ name: String) -> ParsedSampleInfo? {
        let pattern = #"^(.+?)_([A-G][#B]?-?\d+|\d{1,3})_rr(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else {
            return nil
        }
        
        guard let sampleNameRange = Range(match.range(at: 1), in: name),
              let noteRange = Range(match.range(at: 2), in: name),
              let rrRange = Range(match.range(at: 3), in: name) else {
            return nil
        }
        
        let sampleName = String(name[sampleNameRange])
        let noteStr = String(name[noteRange])
        let rrStr = String(name[rrRange])
        
        let midiNote = Int(noteStr) ?? noteNameToMidi(noteStr)
        
        guard let rr = Int(rrStr) else {
            return nil
        }
        
        return ParsedSampleInfo(
            originalFileName: name,
            sampleName: sampleName,
            midiNote: midiNote,
            velocityRange: (min: 0, max: 127), // Default full velocity
            roundRobinIndex: rr
        )
    }
    
    /// Parse pattern: SampleName_C3 or SampleName_48
    private static func parseNoteOnlyPattern(_ name: String) -> ParsedSampleInfo? {
        let pattern = #"^(.+?)_([A-G][#B]?-?\d+|\d{1,3})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else {
            return nil
        }
        
        guard let sampleNameRange = Range(match.range(at: 1), in: name),
              let noteRange = Range(match.range(at: 2), in: name) else {
            return nil
        }
        
        let sampleName = String(name[sampleNameRange])
        let noteStr = String(name[noteRange])
        
        let midiNote = Int(noteStr) ?? noteNameToMidi(noteStr)
        
        return ParsedSampleInfo(
            originalFileName: name,
            sampleName: sampleName,
            midiNote: midiNote,
            velocityRange: (min: 0, max: 127), // Default full velocity
            roundRobinIndex: nil
        )
    }
    
    // MARK: - Batch Processing
    
    /// Parse multiple filenames and group them by target mapping
    static func parseBatch(fileURLs: [URL]) -> [ParsedSampleInfo] {
        return fileURLs.map { url in
            parse(fileName: url.lastPathComponent)
        }
    }
    
    /// Group parsed samples by MIDI note for easier processing
    static func groupByNote(_ parsedSamples: [ParsedSampleInfo]) -> [Int: [ParsedSampleInfo]] {
        var grouped: [Int: [ParsedSampleInfo]] = [:]
        
        for sample in parsedSamples {
            guard let note = sample.midiNote else { continue }
            if grouped[note] == nil {
                grouped[note] = []
            }
            grouped[note]?.append(sample)
        }
        
        return grouped
    }
}

// MARK: - Testing
extension FileNameParser {
    /// Test the parser with example filenames
    static func runTests() {
        let testFileNames = [
            "Kick_C1_v0-40_rr1.wav",
            "Kick_C1_v0-40_rr2.wav",
            "Kick_C1_v41-80_rr1.wav",
            "Snare_D1_v0-127.wav",
            "HiHat_F#1_rr1.wav",
            "HiHat_F#1_rr2.wav",
            "Crash_49.wav",
            "Tom_48_v0-60.wav",
            "SimpleSample.wav"
        ]
        
        print("FileNameParser Test Results:")
        print("============================")
        
        for fileName in testFileNames {
            let result = parse(fileName: fileName)
            print("\nFile: \(fileName)")
            print("Parsed: \(result.description)")
        }
    }
}