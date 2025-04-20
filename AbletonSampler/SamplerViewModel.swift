// File: HabitStacker/SamplerViewModel.swift
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers // Needed for UTType

// Represents a single slot for a sample, corresponding to a MIDI note
struct SampleSlot: Identifiable {
    let id = UUID() // Conformance to Identifiable
    let midiNote: Int // MIDI note number (0-11 for C-2 to B-2)
    var fileURL: URL? = nil // URL of the dropped .wav file
    var fileName: String? = nil
    var sampleRate: Double? = nil
    var frameCount: Int64? = nil // Duration in sample frames
    var fileSize: Int64? = nil // File size in bytes

    // Helper to get MIDI note name (e.g., C-2, C#-2)
    var midiNoteName: String {
        let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        // Assuming MIDI note 0 is C-2 (as per Ableton's convention in Simpler/Sampler)
        let octave = -2
        let noteIndex = midiNote % 12
        return "\(notes[noteIndex])\(octave)"
    }
}

// Manages the state of the sample slots and XML generation
class SamplerViewModel: ObservableObject {
    @Published var slots: [SampleSlot] = [] // The 12 slots
    @Published var showingExportModal = false // Controls the export modal presentation
    @Published var generatedXml: String = "" // Holds the generated XML

    // MIDI note names for display
    let midiNoteNames: [String] = (0..<12).map { index in
        let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = -2 // Standard Ableton octave for lowest notes
        let noteIndex = index % 12
        return "\(notes[noteIndex])\(octave)"
    }


    init() {
        // Initialize 12 empty slots for MIDI notes 0 to 11
        for i in 0..<12 {
            slots.append(SampleSlot(midiNote: i))
        }
        print("SamplerViewModel initialized with \(slots.count) slots.")
    }

    // Function to update a slot when a file is dropped
    func updateSlot(midiNote: Int, fileURL: URL) {
        guard let index = slots.firstIndex(where: { $0.midiNote == midiNote }) else {
            print("Error: Could not find slot for MIDI note \(midiNote)")
            return
        }

        // Ensure it's a WAV file
        guard fileURL.pathExtension.lowercased() == "wav" else {
            print("Error: Dropped file is not a .wav file: \(fileURL.lastPathComponent)")
            // Optionally show an alert to the user here
            return
        }
        
        print("Processing dropped file: \(fileURL.path)")


        // Extract metadata
        var sampleRate: Double? = nil
        var frameCount: Int64? = nil
        var fileSize: Int64? = nil

        // Get file size
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = attributes[.size] as? Int64
            print("File size: \(fileSize ?? -1)")
        } catch {
            print("Error getting file attributes for \(fileURL.path): \(error)")
        }

        // Get audio metadata using AVFoundation
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let format = audioFile.processingFormat
            sampleRate = format.sampleRate
            frameCount = audioFile.length // This is the length in sample frames
            print("Sample Rate: \(sampleRate ?? -1), Frame Count: \(frameCount ?? -1)")
        } catch {
            print("Error reading audio file metadata for \(fileURL.path): \(error)")
            // Handle error - maybe clear the slot or show an error message
             slots[index].fileURL = nil
             slots[index].fileName = nil
             slots[index].sampleRate = nil
             slots[index].frameCount = nil
             slots[index].fileSize = nil
            // Consider showing an alert to the user
             return // Stop processing if we can't read the audio file
        }

        // Update the specific slot
        // Using objectWillChange.send() before mutation helps SwiftUI update views reliably
        objectWillChange.send()
        slots[index].fileURL = fileURL
        slots[index].fileName = fileURL.deletingPathExtension().lastPathComponent // Store filename without extension
        slots[index].sampleRate = sampleRate
        slots[index].frameCount = frameCount
        slots[index].fileSize = fileSize
        
        print("Updated slot \(midiNote) with file: \(slots[index].fileName ?? "N/A")")

    }

    // Function to generate the XML content
    func generateXmlForExport() {
         print("Starting XML generation...")
         let samplePartsXml = generateSamplePartsXml()
         print("Generated Sample Parts XML:\n\(samplePartsXml)") // Debug print
        
        // Use the second example XML as the base template.
        // Replace the placeholder comment inside <SampleParts> with the generated XML.
         let baseXmlTemplate = """
 <?xml version="1.0" encoding="UTF-8"?>
 <Ableton MajorVersion="5" MinorVersion="12.0_12120" SchemaChangeCount="4" Creator="Ableton Live 12.1.11" Revision="ce4b7c22b06532409b78ca241e5bb73735e7ca10">
     <MultiSampler>
         <LomId Value="0" />
         <LomIdView Value="0" />
         <IsExpanded Value="true" />
         <BreakoutIsExpanded Value="false" />
         <On>
             <LomId Value="0" />
             <Manual Value="true" />
             <AutomationTarget Id="0">
                 <LockEnvelope Value="0" />
             </AutomationTarget>
             <MidiCCOnOffThresholds>
                 <Min Value="64" />
                 <Max Value="127" />
             </MidiCCOnOffThresholds>
         </On>
         <ModulationSourceCount Value="0" />
         <ParametersListWrapper LomId="0" />
         <Pointee Id="0" />
         <LastSelectedTimeableIndex Value="0" />
         <LastSelectedClipEnvelopeIndex Value="0" />
         <LastPresetRef>
             <Value>
                 <!-- Placeholder for Preset Reference - Can be adjusted later -->
                 <FilePresetRef Id="0">
                     <FileRef>
                         <RelativePathType Value="6" />
                         <RelativePath Value="Presets/Instruments/Sampler/GeneratedPreset.adv" />
                         <Path Value="/Users/YOUR_USERNAME/Music/Ableton/User Library/Presets/Instruments/Sampler/GeneratedPreset.adv" />
                         <Type Value="2" />
                         <LivePackName Value="" />
                         <LivePackId Value="" />
                         <OriginalFileSize Value="0" />
                         <OriginalCrc Value="0" />
                     </FileRef>
                 </FilePresetRef>
             </Value>
         </LastPresetRef>
         <LockedScripts />
         <IsFolded Value="false" />
         <ShouldShowPresetName Value="true" />
         <UserName Value="" />
         <Annotation Value="" />
         <SourceContext>
             <Value />
         </SourceContext>
         <MpePitchBendUsesTuning Value="true" />
         <OverwriteProtectionNumber Value="3073" />
         <Player>
             <MultiSampleMap>
                 <SampleParts>
                     <!-- DYNAMIC CONTENT START -->
                     \(samplePartsXml)
                     <!-- DYNAMIC CONTENT END -->
                 </SampleParts>
                 <LoadInRam Value="false" />
                 <LayerCrossfade Value="0" />
                 <SourceContext />
                 <RoundRobin Value="false" />
                 <RoundRobinMode Value="0" />
                 <RoundRobinResetPeriod Value="0" />
                 <!-- Generate a somewhat random seed -->
                 <RoundRobinRandomSeed Value="\(Int.random(in: -2000000000...2000000000))" />
             </MultiSampleMap>
             <LoopModulators>
                 <IsModulated Value="false" />
                 <SampleStart>
                     <LomId Value="0" />
                     <Manual Value="0" />
                     <MidiControllerRange>
                         <Min Value="0" />
                         <Max Value="1" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </SampleStart>
                 <SampleLength>
                     <LomId Value="0" />
                     <Manual Value="1" />
                     <MidiControllerRange>
                         <Min Value="0" />
                         <Max Value="1" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </SampleLength>
                 <LoopOn>
                     <LomId Value="0" />
                     <Manual Value="false" />
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <MidiCCOnOffThresholds>
                         <Min Value="64" />
                         <Max Value="127" />
                     </MidiCCOnOffThresholds>
                 </LoopOn>
                 <LoopLength>
                     <LomId Value="0" />
                     <Manual Value="1" />
                     <MidiControllerRange>
                         <Min Value="0" />
                         <Max Value="1" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </LoopLength>
                 <LoopFade>
                     <LomId Value="0" />
                     <Manual Value="0" />
                     <MidiControllerRange>
                         <Min Value="0" />
                         <Max Value="1" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </LoopFade>
             </LoopModulators>
             <Reverse>
                 <LomId Value="0" />
                 <Manual Value="false" />
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <MidiCCOnOffThresholds>
                     <Min Value="64" />
                     <Max Value="127" />
                 </MidiCCOnOffThresholds>
             </Reverse>
             <Snap>
                 <LomId Value="0" />
                 <Manual Value="false" />
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <MidiCCOnOffThresholds>
                     <Min Value="64" />
                     <Max Value="127" />
                 </MidiCCOnOffThresholds>
             </Snap>
             <SampleSelector>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="0" />
                     <Max Value="127" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </SampleSelector>
             <SubOsc>
                 <IsOn>
                     <LomId Value="0" />
                     <Manual Value="false" />
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <MidiCCOnOffThresholds>
                         <Min Value="64" />
                         <Max Value="127" />
                     </MidiCCOnOffThresholds>
                 </IsOn>
                 <Slot>
                     <Value />
                 </Slot>
             </SubOsc>
             <InterpolationMode Value="3" />
             <UseConstPowCrossfade Value="true" />
         </Player>
         <Pitch>
             <TransposeKey>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="-48" />
                     <Max Value="48" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </TransposeKey>
             <TransposeFine>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="-50" />
                     <Max Value="50" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </TransposeFine>
             <PitchLfoAmount>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="0" />
                     <Max Value="1" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </PitchLfoAmount>
             <Envelope>
                 <IsOn>
                     <LomId Value="0" />
                     <Manual Value="false" />
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <MidiCCOnOffThresholds>
                         <Min Value="64" />
                         <Max Value="127" />
                     </MidiCCOnOffThresholds>
                 </IsOn>
                 <Slot>
                     <Value />
                 </Slot>
             </Envelope>
             <ScrollPosition Value="-1073741824" />
         </Pitch>
         <Filter>
             <IsOn>
                 <LomId Value="0" />
                 <Manual Value="true" />
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <MidiCCOnOffThresholds>
                     <Min Value="64" />
                     <Max Value="127" />
                 </MidiCCOnOffThresholds>
             </IsOn>
             <Slot>
                 <Value>
                     <SimplerFilter Id="0">
                         <LegacyType>
                             <LomId Value="0" />
                             <Manual Value="0" />
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                         </LegacyType>
                         <Type>
                             <LomId Value="0" />
                             <Manual Value="0" />
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                         </Type>
                         <CircuitLpHp>
                             <LomId Value="0" />
                             <Manual Value="0" />
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                         </CircuitLpHp>
                         <CircuitBpNoMo>
                             <LomId Value="0" />
                             <Manual Value="0" />
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                         </CircuitBpNoMo>
                         <Slope>
                             <LomId Value="0" />
                             <Manual Value="true" />
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                             <MidiCCOnOffThresholds>
                                 <Min Value="64" />
                                 <Max Value="127" />
                             </MidiCCOnOffThresholds>
                         </Slope>
                         <Freq>
                             <LomId Value="0" />
                             <Manual Value="22000" />
                             <MidiControllerRange>
                                 <Min Value="30" />
                                 <Max Value="22000" />
                             </MidiControllerRange>
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                             <ModulationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </ModulationTarget>
                         </Freq>
                         <LegacyQ>
                             <LomId Value="0" />
                             <Manual Value="0.6999999881" />
                             <MidiControllerRange>
                                 <Min Value="0.3000000119" />
                                 <Max Value="10" />
                             </MidiControllerRange>
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                             <ModulationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </ModulationTarget>
                         </LegacyQ>
                         <Res>
                             <LomId Value="0" />
                             <Manual Value="0.09090908617" />
                             <MidiControllerRange>
                                 <Min Value="0" />
                                 <Max Value="1.25" />
                             </MidiControllerRange>
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                             <ModulationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </ModulationTarget>
                         </Res>
                         <X>
                             <LomId Value="0" />
                             <Manual Value="0" />
                             <MidiControllerRange>
                                 <Min Value="0" />
                                 <Max Value="1" />
                             </MidiControllerRange>
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                             <ModulationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </ModulationTarget>
                         </X>
                         <Drive>
                             <LomId Value="0" />
                             <Manual Value="0" />
                             <MidiControllerRange>
                                 <Min Value="0" />
                                 <Max Value="24" />
                             </MidiControllerRange>
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                             <ModulationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </ModulationTarget>
                         </Drive>
                         <Envelope>
                             <AttackTime>
                                 <LomId Value="0" />
                                 <Manual Value="0.1000000015" />
                                 <MidiControllerRange>
                                     <Min Value="0.1000000015" />
                                     <Max Value="20000" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </AttackTime>
                             <AttackLevel>
                                 <LomId Value="0" />
                                 <Manual Value="0" />
                                 <MidiControllerRange>
                                     <Min Value="0" />
                                     <Max Value="1" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </AttackLevel>
                             <AttackSlope>
                                 <LomId Value="0" />
                                 <Manual Value="0" />
                                 <MidiControllerRange>
                                     <Min Value="-1" />
                                     <Max Value="1" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </AttackSlope>
                             <DecayTime>
                                 <LomId Value="0" />
                                 <Manual Value="600" />
                                 <MidiControllerRange>
                                     <Min Value="1" />
                                     <Max Value="60000" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </DecayTime>
                             <DecayLevel>
                                 <LomId Value="0" />
                                 <Manual Value="1" />
                                 <MidiControllerRange>
                                     <Min Value="0" />
                                     <Max Value="1" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </DecayLevel>
                             <DecaySlope>
                                 <LomId Value="0" />
                                 <Manual Value="1" />
                                 <MidiControllerRange>
                                     <Min Value="-1" />
                                     <Max Value="1" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </DecaySlope>
                             <SustainLevel>
                                 <LomId Value="0" />
                                 <Manual Value="0" />
                                 <MidiControllerRange>
                                     <Min Value="0" />
                                     <Max Value="1" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </SustainLevel>
                             <ReleaseTime>
                                 <LomId Value="0" />
                                 <Manual Value="50" />
                                 <MidiControllerRange>
                                     <Min Value="1" />
                                     <Max Value="60000" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </ReleaseTime>
                             <ReleaseLevel>
                                 <LomId Value="0" />
                                 <Manual Value="0" />
                                 <MidiControllerRange>
                                     <Min Value="0" />
                                     <Max Value="1" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </ReleaseLevel>
                             <ReleaseSlope>
                                 <LomId Value="0" />
                                 <Manual Value="1" />
                                 <MidiControllerRange>
                                     <Min Value="-1" />
                                     <Max Value="1" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </ReleaseSlope>
                             <LoopMode>
                                 <LomId Value="0" />
                                 <Manual Value="0" />
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                             </LoopMode>
                             <LoopTime>
                                 <LomId Value="0" />
                                 <Manual Value="100" />
                                 <MidiControllerRange>
                                     <Min Value="0.200000003" />
                                     <Max Value="20000" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </LoopTime>
                             <RepeatTime>
                                 <LomId Value="0" />
                                 <Manual Value="3" />
                                 <MidiControllerRange>
                                     <Min Value="0" />
                                     <Max Value="14" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </RepeatTime>
                             <TimeVelScale>
                                 <LomId Value="0" />
                                 <Manual Value="0" />
                                 <MidiControllerRange>
                                     <Min Value="-100" />
                                     <Max Value="100" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </TimeVelScale>
                             <CurrentOverlay Value="0" />
                             <IsOn>
                                 <LomId Value="0" />
                                 <Manual Value="true" />
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <MidiCCOnOffThresholds>
                                     <Min Value="64" />
                                     <Max Value="127" />
                                 </MidiCCOnOffThresholds>
                             </IsOn>
                             <Amount>
                                 <LomId Value="0" />
                                 <Manual Value="0" />
                                 <MidiControllerRange>
                                     <Min Value="-72" />
                                     <Max Value="72" />
                                 </MidiControllerRange>
                                 <AutomationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </AutomationTarget>
                                 <ModulationTarget Id="0">
                                     <LockEnvelope Value="0" />
                                 </ModulationTarget>
                             </Amount>
                             <ScrollPosition Value="0" />
                         </Envelope>
                         <ModByPitch>
                             <LomId Value="0" />
                             <Manual Value="1" />
                             <MidiControllerRange>
                                 <Min Value="0" />
                                 <Max Value="1" />
                             </MidiControllerRange>
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                             <ModulationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </ModulationTarget>
                         </ModByPitch>
                         <ModByVelocity>
                             <LomId Value="0" />
                             <Manual Value="0" />
                             <MidiControllerRange>
                                 <Min Value="0" />
                                 <Max Value="1" />
                             </MidiControllerRange>
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                             <ModulationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </ModulationTarget>
                         </ModByVelocity>
                         <ModByLfo>
                             <LomId Value="0" />
                             <Manual Value="0" />
                             <MidiControllerRange>
                                 <Min Value="0" />
                                 <Max Value="24" />
                             </MidiControllerRange>
                             <AutomationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </AutomationTarget>
                             <ModulationTarget Id="0">
                                 <LockEnvelope Value="0" />
                             </ModulationTarget>
                         </ModByLfo>
                     </SimplerFilter>
                 </Value>
             </Slot>
         </Filter>
         <Shaper>
             <IsOn>
                 <LomId Value="0" />
                 <Manual Value="false" />
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <MidiCCOnOffThresholds>
                     <Min Value="64" />
                     <Max Value="127" />
                 </MidiCCOnOffThresholds>
             </IsOn>
             <Slot>
                 <Value />
             </Slot>
         </Shaper>
         <VolumeAndPan>
             <Volume>
                 <LomId Value="0" />
                 <Manual Value="-12" />
                 <MidiControllerRange>
                     <Min Value="-36" />
                     <Max Value="36" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </Volume>
             <VolumeVelScale>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="0" />
                     <Max Value="1" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </VolumeVelScale>
             <VolumeKeyScale>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="-1" />
                     <Max Value="1" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </VolumeKeyScale>
             <VolumeLfoAmount>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="0" />
                     <Max Value="1" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </VolumeLfoAmount>
             <Panorama>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="-1" />
                     <Max Value="1" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </Panorama>
             <PanoramaKeyScale>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="-1" />
                     <Max Value="1" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </PanoramaKeyScale>
             <PanoramaRnd>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="0" />
                     <Max Value="1" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </PanoramaRnd>
             <PanoramaLfoAmount>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="0" />
                     <Max Value="1" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </PanoramaLfoAmount>
             <Envelope>
                 <AttackTime>
                     <LomId Value="0" />
                     <Manual Value="0.1000000015" />
                     <MidiControllerRange>
                         <Min Value="0.1000000015" />
                         <Max Value="20000" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </AttackTime>
                 <AttackLevel>
                     <LomId Value="0" />
                     <Manual Value="0.0003162277571" />
                     <MidiControllerRange>
                         <Min Value="0.0003162277571" />
                         <Max Value="1" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </AttackLevel>
                 <AttackSlope>
                     <LomId Value="0" />
                     <Manual Value="0" />
                     <MidiControllerRange>
                         <Min Value="-1" />
                         <Max Value="1" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </AttackSlope>
                 <DecayTime>
                     <LomId Value="0" />
                     <Manual Value="600" />
                     <MidiControllerRange>
                         <Min Value="1" />
                         <Max Value="60000" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </DecayTime>
                 <DecayLevel>
                     <LomId Value="0" />
                     <Manual Value="1" />
                     <MidiControllerRange>
                         <Min Value="0.0003162277571" />
                         <Max Value="1" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </DecayLevel>
                 <DecaySlope>
                     <LomId Value="0" />
                     <Manual Value="1" />
                     <MidiControllerRange>
                         <Min Value="-1" />
                         <Max Value="1" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </DecaySlope>
                 <SustainLevel>
                     <LomId Value="0" />
                     <Manual Value="1" />
                     <MidiControllerRange>
                         <Min Value="0.0003162277571" />
                         <Max Value="1" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </SustainLevel>
                 <ReleaseTime>
                     <LomId Value="0" />
                     <Manual Value="50" />
                     <MidiControllerRange>
                         <Min Value="1" />
                         <Max Value="60000" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </ReleaseTime>
                 <ReleaseLevel>
                     <LomId Value="0" />
                     <Manual Value="0.0003162277571" />
                     <MidiControllerRange>
                         <Min Value="0.0003162277571" />
                         <Max Value="1" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </ReleaseLevel>
                 <ReleaseSlope>
                     <LomId Value="0" />
                     <Manual Value="1" />
                     <MidiControllerRange>
                         <Min Value="-1" />
                         <Max Value="1" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </ReleaseSlope>
                 <LoopMode>
                     <LomId Value="0" />
                     <Manual Value="0" />
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                 </LoopMode>
                 <LoopTime>
                     <LomId Value="0" />
                     <Manual Value="100" />
                     <MidiControllerRange>
                         <Min Value="0.200000003" />
                         <Max Value="20000" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </LoopTime>
                 <RepeatTime>
                     <LomId Value="0" />
                     <Manual Value="3" />
                     <MidiControllerRange>
                         <Min Value="0" />
                         <Max Value="14" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </RepeatTime>
                 <TimeVelScale>
                     <LomId Value="0" />
                     <Manual Value="0" />
                     <MidiControllerRange>
                         <Min Value="-100" />
                         <Max Value="100" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </TimeVelScale>
                 <CurrentOverlay Value="0" />
             </Envelope>
             <OneShotEnvelope>
                 <FadeInTime>
                     <LomId Value="0" />
                     <Manual Value="0.1000000015" />
                     <MidiControllerRange>
                         <Min Value="0" />
                         <Max Value="2000" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </FadeInTime>
                 <SustainMode>
                     <LomId Value="0" />
                     <Manual Value="0" />
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                 </SustainMode>
                 <FadeOutTime>
                     <LomId Value="0" />
                     <Manual Value="0.1000000015" />
                     <MidiControllerRange>
                         <Min Value="0" />
                         <Max Value="2000" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </FadeOutTime>
             </OneShotEnvelope>
         </VolumeAndPan>
         <AuxEnv>
             <IsOn>
                 <LomId Value="0" />
                 <Manual Value="false" />
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <MidiCCOnOffThresholds>
                     <Min Value="64" />
                     <Max Value="127" />
                 </MidiCCOnOffThresholds>
             </IsOn>
             <Slot>
                 <Value />
             </Slot>
         </AuxEnv>
         <Lfo>
             <IsOn>
                 <LomId Value="0" />
                 <Manual Value="false" />
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <MidiCCOnOffThresholds>
                     <Min Value="64" />
                     <Max Value="127" />
                 </MidiCCOnOffThresholds>
             </IsOn>
             <Slot>
                 <Value />
             </Slot>
         </Lfo>
         <AuxLfos.0>
             <IsOn>
                 <LomId Value="0" />
                 <Manual Value="false" />
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <MidiCCOnOffThresholds>
                     <Min Value="64" />
                     <Max Value="127" />
                 </MidiCCOnOffThresholds>
             </IsOn>
             <Slot>
                 <Value />
             </Slot>
         </AuxLfos.0>
         <AuxLfos.1>
             <IsOn>
                 <LomId Value="0" />
                 <Manual Value="false" />
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <MidiCCOnOffThresholds>
                     <Min Value="64" />
                     <Max Value="127" />
                 </MidiCCOnOffThresholds>
             </IsOn>
             <Slot>
                 <Value />
             </Slot>
         </AuxLfos.1>
         <KeyDst>
             <ModConnections.0>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.0>
             <ModConnections.1>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.1>
         </KeyDst>
         <VelDst>
             <ModConnections.0>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.0>
             <ModConnections.1>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.1>
         </VelDst>
         <RelVelDst>
             <ModConnections.0>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.0>
             <ModConnections.1>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.1>
         </RelVelDst>
         <MidiCtrl.0>
             <ModConnections.0>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.0>
             <ModConnections.1>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.1>
             <Feedback Value="0" />
         </MidiCtrl.0>
         <MidiCtrl.1>
             <ModConnections.0>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.0>
             <ModConnections.1>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.1>
             <Feedback Value="0" />
         </MidiCtrl.1>
         <MidiCtrl.2>
             <ModConnections.0>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.0>
             <ModConnections.1>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.1>
             <Feedback Value="0" />
         </MidiCtrl.2>
         <MidiCtrl.3>
             <ModConnections.0>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.0>
             <ModConnections.1>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.1>
             <Feedback Value="0" />
         </MidiCtrl.3>
         <MidiCtrl.4>
             <ModConnections.0>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.0>
             <ModConnections.1>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.1>
             <Feedback Value="0" />
         </MidiCtrl.4>
         <MidiCtrl.5>
             <ModConnections.0>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.0>
             <ModConnections.1>
                 <Amount Value="0" />
                 <Connection Value="0" />
             </ModConnections.1>
             <Feedback Value="0" />
         </MidiCtrl.5>
         <Globals>
             <NumVoices Value="5" />
             <NumVoicesEnvTimeControl Value="false" />
             <RetriggerMode Value="true" />
             <ModulationResolution Value="2" />
             <SpreadAmount>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="0" />
                     <Max Value="100" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </SpreadAmount>
             <KeyZoneShift>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <MidiControllerRange>
                     <Min Value="-48" />
                     <Max Value="48" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </KeyZoneShift>
             <PortamentoMode>
                 <LomId Value="0" />
                 <Manual Value="0" />
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
             </PortamentoMode>
             <PortamentoTime>
                 <LomId Value="0" />
                 <Manual Value="50" />
                 <MidiControllerRange>
                     <Min Value="0.1000000015" />
                     <Max Value="10000" />
                 </MidiControllerRange>
                 <AutomationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </AutomationTarget>
                 <ModulationTarget Id="0">
                     <LockEnvelope Value="0" />
                 </ModulationTarget>
             </PortamentoTime>
             <PitchBendRange Value="5" />
             <MpePitchBendRange Value="48" />
             <ScrollPosition Value="0" />
             <EnvScale>
                 <EnvTime>
                     <LomId Value="0" />
                     <Manual Value="0" />
                     <MidiControllerRange>
                         <Min Value="-100" />
                         <Max Value="100" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </EnvTime>
                 <EnvTimeKeyScale>
                     <LomId Value="0" />
                     <Manual Value="0" />
                     <MidiControllerRange>
                         <Min Value="-100" />
                         <Max Value="100" />
                     </MidiControllerRange>
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <ModulationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </ModulationTarget>
                 </EnvTimeKeyScale>
                 <EnvTimeIncludeAttack>
                     <LomId Value="0" />
                     <Manual Value="true" />
                     <AutomationTarget Id="0">
                         <LockEnvelope Value="0" />
                     </AutomationTarget>
                     <MidiCCOnOffThresholds>
                         <Min Value="64" />
                         <Max Value="127" />
                     </MidiCCOnOffThresholds>
                 </EnvTimeIncludeAttack>
             </EnvScale>
             <IsSimpler Value="false" />
             <PlaybackMode Value="0" />
             <LegacyMode Value="false" />
         </Globals>
         <ViewSettings>
             <SelectedPage Value="0" />
             <ZoneEditorVisible Value="true" />
             <Seconds Value="false" />
             <SelectedSampleChannel Value="0" />
             <VerticalSampleZoom Value="1" />
             <IsAutoSelectEnabled Value="false" />
             <SimplerBreakoutVisible Value="false" />
         </ViewSettings>
         <SimplerSlicing>
             <PlaybackMode Value="0" />
         </SimplerSlicing>
     </MultiSampler>
 </Ableton>
 """
        
        // Update the published property, which will trigger the modal presentation
        self.generatedXml = baseXmlTemplate
        self.showingExportModal = true
        print("XML generation complete. Showing modal.")
    }

    // Helper function to generate the <MultiSamplePart> elements
    private func generateSamplePartsXml() -> String {
        var resultXml = ""
        var currentId = 0 // Keep track of the sequential ID for MultiSamplePart

        for slot in slots {
            // Only generate a part if a file URL exists for the slot
            guard let fileURL = slot.fileURL else { continue }

            // Use fetched metadata or provide safe defaults
            let fileName = slot.fileName ?? "Sample"
            // Default duration needs to be at least 1 for SampleEnd calculation
            let defaultDuration = max(1, slot.frameCount ?? 1)
            let sampleEnd = defaultDuration - 1
            let defaultSampleRate = Int(slot.sampleRate ?? 44100)
            let originalFileSize = slot.fileSize ?? 0
            let originalCrc = 0 // Hardcoded CRC as 0 for now
            let absolutePath = fileURL.path
            // Construct a plausible relative path assuming User Library structure
            let relativePath = "Samples/Imported/\(fileURL.lastPathComponent)"
            // Unix timestamp for LastModDate (can use current time)
            let lastModDate = Int(Date().timeIntervalSince1970)
            let midiNote = slot.midiNote

            // Append the XML for this MultiSamplePart, indented for readability
            // Most values are hardcoded based on the example for now
            resultXml += """
                     <MultiSamplePart Id="\(currentId)" InitUpdateAreSlicesFromOnsetsEditableAfterRead="false" HasImportedSlicePoints="false" NeedsAnalysisData="false">
                         <LomId Value="0" />
                         <Name Value="\(fileName)" />
                         <Selection Value="false" />
                         <IsActive Value="true" />
                         <Solo Value="false" />
                         <KeyRange>
                             <Min Value="\(midiNote)" />
                             <Max Value="\(midiNote)" />
                             <CrossfadeMin Value="\(midiNote)" />
                             <CrossfadeMax Value="\(midiNote)" />
                         </KeyRange>
                         <VelocityRange>
                             <Min Value="1" />
                             <Max Value="127" />
                             <CrossfadeMin Value="1" />
                             <CrossfadeMax Value="127" />
                         </VelocityRange>
                         <SelectorRange>
                             <Min Value="0" />
                             <Max Value="127" />
                             <CrossfadeMin Value="0" />
                             <CrossfadeMax Value="127" />
                         </SelectorRange>
                         <RootKey Value="60" />
                         <Detune Value="0" />
                         <TuneScale Value="100" />
                         <Panorama Value="0" />
                         <Volume Value="1" />
                         <Link Value="false" />
                         <SampleStart Value="0" />
                         <SampleEnd Value="\(sampleEnd)" />
                         <SustainLoop>
                             <Start Value="0" />
                             <End Value="\(sampleEnd)" />
                             <Mode Value="0" />
                             <Crossfade Value="0" />
                             <Detune Value="0" />
                         </SustainLoop>
                         <ReleaseLoop>
                             <Start Value="0" />
                             <End Value="\(sampleEnd)" />
                             <Mode Value="3" />
                             <Crossfade Value="0" />
                             <Detune Value="0" />
                         </ReleaseLoop>
                         <SampleRef>
                             <FileRef>
                                 <RelativePathType Value="6" />
                                 <RelativePath Value="\(relativePath)" />
                                 <Path Value="\(absolutePath)" />
                                 <Type Value="2" />
                                 <LivePackName Value="" />
                                 <LivePackId Value="" />
                                 <OriginalFileSize Value="\(originalFileSize)" />
                                 <OriginalCrc Value="\(originalCrc)" />
                             </FileRef>
                             <LastModDate Value="\(lastModDate)" />
                             <SourceContext />
                             <SampleUsageHint Value="0" />
                             <DefaultDuration Value="\(defaultDuration)" />
                             <DefaultSampleRate Value="\(defaultSampleRate)" />
                             <SamplesToAutoWarp Value="1" />
                         </SampleRef>
                         <SlicingThreshold Value="100" />
                         <SlicingBeatGrid Value="4" />
                         <SlicingRegions Value="8" />
                         <SlicingStyle Value="0" />
                         <SampleWarpProperties>
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
                     </MultiSamplePart>\n
             """
            currentId += 1 // Increment ID for the next part
        }
        return resultXml
    }
}
