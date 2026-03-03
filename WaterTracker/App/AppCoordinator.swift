import Foundation
import SwiftData
import Observation
import os

private let logger = Logger(subsystem: "com.lucasprim.water-tracker", category: "AppCoordinator")

@MainActor
@Observable
final class AppCoordinator {
    let timerManager: DrinkTimerManager
    let webcamMonitor: WebcamMonitor
    private let modelContext: ModelContext
    private var dayChangeObserver: NSObjectProtocol?
    private var lastDetectionTime: Date = .distantPast
    private let detectionCooldown: TimeInterval = 60

    init(timerManager: DrinkTimerManager, webcamMonitor: WebcamMonitor, modelContext: ModelContext) {
        self.timerManager = timerManager
        self.webcamMonitor = webcamMonitor
        self.modelContext = modelContext
    }

    func start() {
        NotificationService.shared.requestAuthorization()

        let interval = loadDrinkInterval()
        timerManager.start(intervalMinutes: interval)

        timerManager.onExpired = { [weak self] in
            self?.handleTimerExpired()
        }

        webcamMonitor.onDrinkingDetected = { [weak self] in
            self?.handleDrinkingDetected()
        }

        loadCalibration()
        webcamMonitor.start()
        observeDayChange()
    }

    // MARK: - Midnight Rollover

    private func observeDayChange() {
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDayChange()
            }
        }
    }

    private func handleDayChange() {
        let interval = loadDrinkInterval()
        timerManager.start(intervalMinutes: interval)

        if webcamMonitor.status != .running && webcamMonitor.status != .denied {
            webcamMonitor.start()
        }
    }

    // MARK: - Private

    func dismissReminder() {
        guard ScreenEdgeOverlay.shared.isShowing else { return }
        ScreenEdgeOverlay.shared.dismiss()
        let interval = loadDrinkInterval()
        timerManager.start(intervalMinutes: interval)
        logger.notice("Reminder dismissed — timer restarted")
    }

    private func handleDrinkingDetected() {
        // Cooldown: ignore detections within 60 seconds of the last one
        let now = Date()
        guard now.timeIntervalSince(lastDetectionTime) >= detectionCooldown else { return }
        lastDetectionTime = now

        logger.notice("Drinking detected — resetting timer")
        dismissReminder()

        // Always restart the timer when drinking is detected.
        let interval = loadDrinkInterval()
        timerManager.start(intervalMinutes: interval)
    }

    private func handleTimerExpired() {
        ScreenEdgeOverlay.shared.flash()
    }

    private func loadCalibration() {
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? modelContext.fetch(descriptor).first,
              let baseline = settings.calibratedBaselineQuality,
              let drop = settings.calibratedDropThreshold else { return }
        webcamMonitor.loadCalibration(
            baselineArea: baseline,
            dropThreshold: drop,
            bottleHue: settings.bottleColorHue,
            bottleSaturation: settings.bottleColorSaturation,
            hueTolerance: settings.bottleColorHueTolerance,
            satTolerance: settings.bottleColorSatTolerance
        )
    }

    private func loadDrinkInterval() -> Int {
        let descriptor = FetchDescriptor<AppSettings>()
        let settings = try? modelContext.fetch(descriptor).first
        return settings?.drinkIntervalMinutes ?? 15
    }
}
