import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class DailyProgressStore {
    let modelContext: ModelContext

    private(set) var todayTotalMl: Double = 0
    private(set) var goalMl: Double = 2000
    private(set) var bottleSizeMl: Double = 500
    private(set) var presetBottleSizes: [Int] = [250, 350, 500, 750]
    private(set) var currentStreak: Int = 0
    private(set) var weeklyData: [DailyTotal] = []

    var completionPercentage: Double {
        guard goalMl > 0 else { return 0 }
        return min(todayTotalMl / goalMl, 1.0)
    }

    var isGoalReached: Bool {
        todayTotalMl >= goalMl
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    func logBottle(source: EntrySource = .manual) {
        logVolume(bottleSizeMl, source: source)
    }

    func logVolume(_ volumeMl: Double, source: EntrySource = .manual) {
        let entry = WaterEntry(volumeMl: volumeMl, source: source)
        modelContext.insert(entry)
        try? modelContext.save()
        refresh()
    }

    func unlogBottle() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<WaterEntry> { entry in
            entry.timestamp >= startOfDay
        }
        var descriptor = FetchDescriptor<WaterEntry>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        descriptor.fetchLimit = 1

        if let entry = try? modelContext.fetch(descriptor).first {
            modelContext.delete(entry)
            try? modelContext.save()
        }
        refresh()
    }

    func refresh() {
        loadSettings()
        loadTodayEntries()
        loadStreak()
        loadWeeklyData()
    }

    func resetToday() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<WaterEntry> { entry in
            entry.timestamp >= startOfDay
        }
        let descriptor = FetchDescriptor<WaterEntry>(predicate: predicate)
        if let entries = try? modelContext.fetch(descriptor) {
            for entry in entries {
                modelContext.delete(entry)
            }
            try? modelContext.save()
        }
        refresh()
    }

    // MARK: - Private

    private func loadSettings() {
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            goalMl = settings.dailyGoalMl
            bottleSizeMl = settings.bottleSizeMl
            presetBottleSizes = settings.resolvedPresetBottleSizes
        } else {
            let defaults = AppSettings()
            modelContext.insert(defaults)
            try? modelContext.save()
            goalMl = defaults.dailyGoalMl
            bottleSizeMl = defaults.bottleSizeMl
            presetBottleSizes = defaults.resolvedPresetBottleSizes
        }
    }

    private func loadTodayEntries() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<WaterEntry> { entry in
            entry.timestamp >= startOfDay
        }
        var descriptor = FetchDescriptor<WaterEntry>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp)]

        let entries = (try? modelContext.fetch(descriptor)) ?? []
        todayTotalMl = entries.reduce(0) { $0 + $1.volumeMl }
    }

    private func loadStreak() {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        // If today's goal is met, include today
        if todayTotalMl >= goalMl {
            streak = 1
        }

        // Walk backwards day by day
        while true {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            let nextDay = checkDate
            let predicate = #Predicate<WaterEntry> { entry in
                entry.timestamp >= previousDay && entry.timestamp < nextDay
            }
            let descriptor = FetchDescriptor<WaterEntry>(predicate: predicate)
            let entries = (try? modelContext.fetch(descriptor)) ?? []
            let dayTotal = entries.reduce(0.0) { $0 + $1.volumeMl }

            if dayTotal >= goalMl {
                streak += 1
                checkDate = previousDay
            } else {
                break
            }
        }
        currentStreak = streak
    }

    private func loadWeeklyData() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var data: [DailyTotal] = []

        for daysAgo in (0..<7).reversed() {
            guard let dayStart = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let predicate = #Predicate<WaterEntry> { entry in
                entry.timestamp >= dayStart && entry.timestamp < dayEnd
            }
            let descriptor = FetchDescriptor<WaterEntry>(predicate: predicate)
            let entries = (try? modelContext.fetch(descriptor)) ?? []
            let total = entries.reduce(0.0) { $0 + $1.volumeMl }

            data.append(DailyTotal(date: dayStart, totalMl: total))
        }
        weeklyData = data
    }
}

struct DailyTotal: Identifiable {
    let id = UUID()
    let date: Date
    let totalMl: Double
}
