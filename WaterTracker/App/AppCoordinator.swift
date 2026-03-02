import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class AppCoordinator {
    let timerManager: DrinkTimerManager
    let webcamMonitor: WebcamMonitor
    private(set) var isFlashingBlue = false
    private let modelContext: ModelContext
    private var store: DailyProgressStore?

    init(timerManager: DrinkTimerManager, webcamMonitor: WebcamMonitor, modelContext: ModelContext) {
        self.timerManager = timerManager
        self.webcamMonitor = webcamMonitor
        self.modelContext = modelContext
    }

    func start() {
        let progressStore = DailyProgressStore(modelContext: modelContext)
        self.store = progressStore

        NotificationService.shared.requestAuthorization()

        let interval = loadDrinkInterval()
        timerManager.start(intervalMinutes: interval)

        timerManager.onExpired = { [weak self] in
            self?.handleTimerExpired()
        }

        webcamMonitor.onDrinkingDetected = { [weak self] in
            self?.handleDrinkingDetected()
        }

        if !progressStore.isGoalReached {
            webcamMonitor.start()
        }
    }

    func handleBottleLogged(isGoalReached: Bool) {
        if isGoalReached {
            timerManager.stop()
            webcamMonitor.stop()
        } else {
            let interval = loadDrinkInterval()
            timerManager.start(intervalMinutes: interval)
        }
    }

    // MARK: - Private

    private func handleDrinkingDetected() {
        guard let store, !store.isGoalReached else { return }

        store.logBottle(source: .webcam)
        flashMenuBarBlue()

        if store.isGoalReached {
            timerManager.stop()
            webcamMonitor.stop()
        } else {
            let interval = loadDrinkInterval()
            timerManager.start(intervalMinutes: interval)
        }
    }

    private func handleTimerExpired() {
        NotificationService.shared.postDrinkReminder()
    }

    private func flashMenuBarBlue() {
        isFlashingBlue = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            isFlashingBlue = false
        }
    }

    private func loadDrinkInterval() -> Int {
        let descriptor = FetchDescriptor<AppSettings>()
        let settings = try? modelContext.fetch(descriptor).first
        return settings?.drinkIntervalMinutes ?? 15
    }
}
