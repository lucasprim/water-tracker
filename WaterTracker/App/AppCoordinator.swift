import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class AppCoordinator {
    let timerManager: DrinkTimerManager
    private let modelContext: ModelContext

    init(timerManager: DrinkTimerManager, modelContext: ModelContext) {
        self.timerManager = timerManager
        self.modelContext = modelContext
    }

    func start() {
        NotificationService.shared.requestAuthorization()

        let interval = loadDrinkInterval()
        timerManager.start(intervalMinutes: interval)

        timerManager.onExpired = { [weak self] in
            self?.handleTimerExpired()
        }
    }

    func handleBottleLogged(isGoalReached: Bool) {
        if isGoalReached {
            timerManager.stop()
        } else {
            let interval = loadDrinkInterval()
            timerManager.start(intervalMinutes: interval)
        }
    }

    // MARK: - Private

    private func handleTimerExpired() {
        NotificationService.shared.postDrinkReminder()
    }

    private func loadDrinkInterval() -> Int {
        let descriptor = FetchDescriptor<AppSettings>()
        let settings = try? modelContext.fetch(descriptor).first
        return settings?.drinkIntervalMinutes ?? 15
    }
}
