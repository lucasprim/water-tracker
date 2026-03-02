import Foundation
import Observation

@MainActor
@Observable
final class DrinkTimerManager {
    private(set) var timeRemaining: TimeInterval = 0
    private(set) var isRunning = false
    private(set) var isExpired = false

    var onExpired: (() -> Void)?

    private var timer: Timer?
    private var intervalSeconds: TimeInterval = 15 * 60

    var formattedTimeRemaining: String {
        guard isRunning, timeRemaining > 0 else { return "" }
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func start(intervalMinutes: Int) {
        intervalSeconds = TimeInterval(intervalMinutes * 60)
        reset()
    }

    func reset() {
        timer?.invalidate()
        timeRemaining = intervalSeconds
        isRunning = true
        isExpired = false
        startTicking()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        timeRemaining = 0
    }

    func tick() {
        guard isRunning, timeRemaining > 0 else { return }
        timeRemaining -= 1
        if timeRemaining <= 0 {
            timeRemaining = 0
            isExpired = true
            isRunning = false
            timer?.invalidate()
            timer = nil
            onExpired?()
        }
    }

    // MARK: - Private

    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
}
