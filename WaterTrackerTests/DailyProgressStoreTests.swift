import Testing
import SwiftData
import Foundation
@testable import Water_Tracker

@MainActor
@Suite("DailyProgressStore Tests")
struct DailyProgressStoreTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([WaterEntry.self, AppSettings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("New store starts at zero")
    func initialState() throws {
        let container = try makeContainer()
        let store = DailyProgressStore(modelContext: container.mainContext)

        #expect(store.todayTotalMl == 0)
        #expect(store.completionPercentage == 0)
        #expect(store.isGoalReached == false)
    }

    @Test("Default settings are created on first launch")
    func defaultSettings() throws {
        let container = try makeContainer()
        let store = DailyProgressStore(modelContext: container.mainContext)

        #expect(store.goalMl == 2000)
        #expect(store.bottleSizeMl == 500)
    }

    @Test("logBottle adds entry with configured bottle size")
    func logBottleAddsEntry() throws {
        let container = try makeContainer()
        let store = DailyProgressStore(modelContext: container.mainContext)

        store.logBottle()

        #expect(store.todayTotalMl == 500)
        #expect(store.completionPercentage == 0.25)
    }

    @Test("Multiple bottles accumulate")
    func multipleBottles() throws {
        let container = try makeContainer()
        let store = DailyProgressStore(modelContext: container.mainContext)

        store.logBottle()
        store.logBottle()
        store.logBottle()

        #expect(store.todayTotalMl == 1500)
        #expect(store.completionPercentage == 0.75)
    }

    @Test("Goal reached at 100%")
    func goalReached() throws {
        let container = try makeContainer()
        let store = DailyProgressStore(modelContext: container.mainContext)

        for _ in 0..<4 {
            store.logBottle()
        }

        #expect(store.todayTotalMl == 2000)
        #expect(store.isGoalReached == true)
        #expect(store.completionPercentage == 1.0)
    }

    @Test("Completion percentage caps at 1.0 when exceeding goal")
    func overconsumption() throws {
        let container = try makeContainer()
        let store = DailyProgressStore(modelContext: container.mainContext)

        for _ in 0..<5 {
            store.logBottle()
        }

        #expect(store.todayTotalMl == 2500)
        #expect(store.completionPercentage == 1.0)
        #expect(store.isGoalReached == true)
    }

    @Test("Entries from yesterday are not counted")
    func midnightReset() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Insert an entry from yesterday
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let oldEntry = WaterEntry(volumeMl: 500)
        oldEntry.timestamp = yesterday
        context.insert(oldEntry)
        try context.save()

        let store = DailyProgressStore(modelContext: context)

        #expect(store.todayTotalMl == 0)
        #expect(store.isGoalReached == false)
    }

    @Test("Custom settings are respected")
    func customSettings() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let settings = AppSettings(bottleSizeMl: 750, dailyGoalMl: 3000, drinkIntervalMinutes: 20)
        context.insert(settings)
        try context.save()

        let store = DailyProgressStore(modelContext: context)

        #expect(store.bottleSizeMl == 750)
        #expect(store.goalMl == 3000)

        store.logBottle()

        #expect(store.todayTotalMl == 750)
        #expect(store.completionPercentage == 0.25)
    }

    @Test("Webcam source entries are logged correctly")
    func webcamSource() throws {
        let container = try makeContainer()
        let store = DailyProgressStore(modelContext: container.mainContext)

        store.logBottle(source: .webcam)

        #expect(store.todayTotalMl == 500)

        let entries = try container.mainContext.fetch(FetchDescriptor<WaterEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.source == .webcam)
    }
}
