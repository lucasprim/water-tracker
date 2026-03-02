import SwiftUI
import SwiftData

@main
struct WaterTrackerApp: App {
    var body: some Scene {
        MenuBarExtra {
            PopoverContentView()
        } label: {
            Label("Water Tracker", systemImage: "drop.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
