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
}
