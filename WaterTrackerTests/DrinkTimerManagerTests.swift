import Testing
import Foundation
@testable import Water_Tracker

@MainActor
@Suite("DrinkTimerManager Tests")
struct DrinkTimerManagerTests {

    @Test("Start sets time remaining to interval")
    func startSetsTimeRemaining() {
        let timer = DrinkTimerManager()
        timer.start(intervalMinutes: 10)

        #expect(timer.timeRemaining == 600)
        #expect(timer.isRunning == true)
        #expect(timer.isExpired == false)
    }

    @Test("Formatted time shows minutes and seconds")
    func formattedTime() {
        let timer = DrinkTimerManager()
        timer.start(intervalMinutes: 15)

        #expect(timer.formattedTimeRemaining == "15:00")
    }

    @Test("Tick decrements time remaining")
    func tickDecrements() {
        let timer = DrinkTimerManager()
        timer.start(intervalMinutes: 1)

        timer.tick()

        #expect(timer.timeRemaining == 59)
        #expect(timer.isRunning == true)
    }

    @Test("Timer expires when reaching zero")
    func timerExpires() {
        let timer = DrinkTimerManager()
        timer.start(intervalMinutes: 1)

        // Tick down to zero
        for _ in 0..<60 {
            timer.tick()
        }

        #expect(timer.timeRemaining == 0)
        #expect(timer.isExpired == true)
        #expect(timer.isRunning == false)
    }

    @Test("onExpired callback fires when timer reaches zero")
    func onExpiredCallback() {
        let timer = DrinkTimerManager()
        var callbackFired = false
        timer.onExpired = { callbackFired = true }

        timer.start(intervalMinutes: 1)

        for _ in 0..<60 {
            timer.tick()
        }

        #expect(callbackFired == true)
    }

    @Test("Reset restores time to interval")
    func resetRestoresTime() {
        let timer = DrinkTimerManager()
        timer.start(intervalMinutes: 5)

        // Tick a few times
        for _ in 0..<10 {
            timer.tick()
        }
        #expect(timer.timeRemaining == 290)

        timer.reset()

        #expect(timer.timeRemaining == 300)
        #expect(timer.isRunning == true)
        #expect(timer.isExpired == false)
    }

    @Test("Stop clears timer state")
    func stopClearsState() {
        let timer = DrinkTimerManager()
        timer.start(intervalMinutes: 5)

        timer.stop()

        #expect(timer.timeRemaining == 0)
        #expect(timer.isRunning == false)
        #expect(timer.formattedTimeRemaining == "")
    }

    @Test("Formatted time is empty when stopped")
    func formattedTimeEmptyWhenStopped() {
        let timer = DrinkTimerManager()

        #expect(timer.formattedTimeRemaining == "")
    }
}
