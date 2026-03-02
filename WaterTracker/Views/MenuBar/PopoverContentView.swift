import SwiftUI
import SwiftData

struct PopoverContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store: DailyProgressStore?
    @State private var showingSettings = false
    var timerManager: DrinkTimerManager
    var webcamMonitor: WebcamMonitor

    var body: some View {
        Group {
            if let store {
                if showingSettings {
                    SettingsView {
                        store.refresh()
                        reloadTimerInterval()
                        showingSettings = false
                    } onCancel: {
                        showingSettings = false
                    }
                    .environment(\.modelContext, modelContext)
                } else {
                    PopoverBody(
                        store: store,
                        timerManager: timerManager,
                        webcamMonitor: webcamMonitor,
                        onOpenSettings: { showingSettings = true }
                    )
                }
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

    @MainActor
    private func reloadTimerInterval() {
        guard let store else { return }
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? store.modelContext.fetch(descriptor).first {
            timerManager.start(intervalMinutes: settings.drinkIntervalMinutes)
        } else {
            timerManager.reset()
        }
    }
}

// MARK: - Popover Body

private struct PopoverBody: View {
    @Bindable var store: DailyProgressStore
    var timerManager: DrinkTimerManager
    var webcamMonitor: WebcamMonitor
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            WaterCupView(fillPercentage: store.completionPercentage)

            progressLabel

            if store.isGoalReached {
                goalReachedView
            } else {
                logButton
            }

            if webcamMonitor.status == .denied {
                cameraDeniedView
            }

            Divider()

            settingsButton
        }
        .padding(24)
        .frame(width: 280)
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
                webcamMonitor.stop()
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

            Button("Reset today") {
                store.resetToday()
                reloadTimerInterval()
                webcamMonitor.start()
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }

    private var cameraDeniedView: some View {
        VStack(spacing: 6) {
            Text("Camera access denied")
                .font(.caption)
                .foregroundStyle(.orange)

            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
    }

    private var settingsButton: some View {
        Button {
            onOpenSettings()
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
    PopoverContentView(timerManager: DrinkTimerManager(), webcamMonitor: WebcamMonitor())
        .modelContainer(for: [WaterEntry.self, AppSettings.self], inMemory: true)
}
