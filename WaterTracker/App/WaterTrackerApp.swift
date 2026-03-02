import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.lucasprim.water-tracker", category: "App")

@main
struct WaterTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let container: ModelContainer
    @State private var timerManager = DrinkTimerManager()
    @State private var webcamMonitor = WebcamMonitor()
    @State private var appCoordinator: AppCoordinator?

    init() {
        let schema = Schema([WaterEntry.self, AppSettings.self])
        let config = ModelConfiguration(schema: schema)
        container = try! ModelContainer(for: schema, configurations: [config])
        logger.notice("WaterTrackerApp init — container created")
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverContentView(timerManager: timerManager, webcamMonitor: webcamMonitor)
                .modelContainer(container)
                .onAppear {
                    guard appCoordinator == nil else { return }
                    logger.notice("Starting AppCoordinator from popover onAppear...")
                    let coordinator = AppCoordinator(
                        timerManager: timerManager,
                        webcamMonitor: webcamMonitor,
                        modelContext: container.mainContext
                    )
                    coordinator.start()
                    appCoordinator = coordinator
                }
        } label: {
            MenuBarLabel(
                timerManager: timerManager,
                isFlashing: appCoordinator?.isFlashingBlue ?? false
            )
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Label

private struct MenuBarLabel: View {
    let timerManager: DrinkTimerManager
    var isFlashing: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "drop.fill")
                .foregroundStyle(isFlashing ? .blue : .primary)
            if !timerManager.formattedTimeRemaining.isEmpty {
                Text(timerManager.formattedTimeRemaining)
                    .monospacedDigit()
            }
        }
    }
}
