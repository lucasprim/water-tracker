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
    @State private var cameraDeviceManager = CameraDeviceManager()
    @State private var appCoordinator: AppCoordinator?
    @State private var completionPercentage: Double = 0

    init() {
        let schema = Schema([WaterEntry.self, AppSettings.self])
        let config = ModelConfiguration(schema: schema)
        container = try! ModelContainer(for: schema, configurations: [config])
        logger.notice("WaterTrackerApp init — container created")
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverContentView(
                        timerManager: timerManager,
                        webcamMonitor: webcamMonitor,
                        cameraDeviceManager: cameraDeviceManager,
                        appCoordinator: appCoordinator,
                        completionPercentage: $completionPercentage
                    )
                .modelContainer(container)
                .onAppear {
                    if let coordinator = appCoordinator {
                        coordinator.dismissReminder()
                    } else {
                        logger.notice("Starting AppCoordinator from popover onAppear...")
                        let coordinator = AppCoordinator(
                            timerManager: timerManager,
                            webcamMonitor: webcamMonitor,
                            modelContext: container.mainContext
                        )
                        coordinator.onQuickLog = { [weak coordinator] in
                            // Refresh will happen when popover appears next
                            _ = coordinator
                        }
                        coordinator.start()
                        appCoordinator = coordinator
                    }
                }
        } label: {
            MenuBarLabel(
                timerManager: timerManager,
                webcamMonitor: webcamMonitor,
                completionPercentage: completionPercentage
            )
        }
        .menuBarExtraStyle(.window)

        Window("Calibrate Detection", id: "calibration") {
            CalibrationWindow(webcamMonitor: webcamMonitor)
                .modelContainer(container)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 500)
    }
}

// MARK: - Menu Bar Label

private struct MenuBarLabel: View {
    let timerManager: DrinkTimerManager
    var webcamMonitor: WebcamMonitor
    var completionPercentage: Double

    var body: some View {
        HStack(spacing: 4) {
            if webcamMonitor.isDrinkingActive {
                Image(nsImage: Self.coloredDropImage)
            } else {
                Image(systemName: "drop.fill", variableValue: completionPercentage)
            }
            if !timerManager.formattedTimeRemaining.isEmpty {
                Text(timerManager.formattedTimeRemaining)
                    .monospacedDigit()
            }
        }
    }

    /// Pre-rendered blue drop icon marked as non-template so macOS won't strip the color.
    private static let coloredDropImage: NSImage = {
        let symbol = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Water drop")!
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let configured = symbol.withSymbolConfiguration(config)!

        let size = configured.size
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.systemBlue.set()
            configured.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSColor.systemBlue.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }()
}
