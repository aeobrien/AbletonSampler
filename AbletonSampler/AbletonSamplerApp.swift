// File: HabitStacker/HabitStackerApp.swift
import SwiftUI

@main
struct HabitStackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(SamplerViewModel()) // Provide the view model to the environment
        }
    }
}
