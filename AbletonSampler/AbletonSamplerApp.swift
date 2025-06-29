// File: AbletonSampler/AbletonSampler/AbletonSamplerApp.swift
import SwiftUI

@main
struct AbletonSamplerApp: App {
    // --- Create managers using @StateObject --- 
    @StateObject private var viewModel = SamplerViewModel()
    @StateObject private var midiManager = MIDIManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // --- Inject BOTH into the environment --- 
                .environmentObject(viewModel) 
                .environmentObject(midiManager)
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Export ADV File...") {
                    viewModel.saveAdvFile()
                }
                .keyboardShortcut("S", modifiers: [.command])
            }
        }
    }
}
