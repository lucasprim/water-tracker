import SwiftUI
import SwiftData

@main
struct WaterTrackerApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([WaterEntry.self, AppSettings.self])
        let config = ModelConfiguration(schema: schema)
        container = try! ModelContainer(for: schema, configurations: [config])
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverContentView()
                .modelContainer(container)
        } label: {
            Label("Water Tracker", systemImage: "drop.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
