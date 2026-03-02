import SwiftUI
import SwiftData

struct PopoverContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store: DailyProgressStore?
    var timerManager: DrinkTimerManager

    var body: some View {
        Group {
            if let store {
                PopoverBody(store: store, timerManager: timerManager)
            } else {
                ProgressView()
                    .frame(width: 280, height: 300)
            }
        }
        .onAppear {
            if store == nil {
                store = DailyProgressStore(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Popover Body

private struct PopoverBody: View {
    @Bindable var store: DailyProgressStore
    var timerManager: DrinkTimerManager
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 16) {
            WaterCupView(fillPercentage: store.completionPercentage)

            progressLabel

            if store.isGoalReached {
                goalReachedView
            } else {
                logButton
            }

            Divider()

            settingsButton
        }
        .padding(24)
        .frame(width: 280)
        .sheet(isPresented: $showingSettings) {
            SettingsView {
                store.refresh()
                timerManager.start(intervalMinutes: Int(store.bottleSizeMl > 0 ? 15 : 15))
                reloadTimerInterval()
            }
        }
    }

    // MARK: - Subviews

    private var progressLabel: some View {
        Text(progressText)
            .font(.system(.title3, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
    }

    private var logButton: some View {
        Button {
            store.logBottle()
            if store.isGoalReached {
                timerManager.stop()
            } else {
                reloadTimerInterval()
            }
        } label: {
            Label("Log Bottle", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .controlSize(.large)
    }

    private var goalReachedView: some View {
        VStack(spacing: 8) {
            Text("Goal reached!")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.green)

            Text("Great job staying hydrated today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
                .font(.subheadline)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private var progressText: String {
        let current = Int(store.todayTotalMl)
        let goal = Int(store.goalMl)
        return formatMl(current) + " / " + formatMl(goal) + " ml"
    }

    private func formatMl(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    @MainActor
    private func reloadTimerInterval() {
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? store.modelContext.fetch(descriptor).first {
            timerManager.start(intervalMinutes: settings.drinkIntervalMinutes)
        } else {
            timerManager.reset()
        }
    }
}

#Preview {
    PopoverContentView(timerManager: DrinkTimerManager())
        .modelContainer(for: [WaterEntry.self, AppSettings.self], inMemory: true)
}
