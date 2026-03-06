import SwiftUI
import SwiftData
import AppKit

struct PopoverContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @State private var store: DailyProgressStore?
    @State private var showingSettings = false
    var timerManager: DrinkTimerManager
    var webcamMonitor: WebcamMonitor
    var cameraDeviceManager: CameraDeviceManager?
    var appCoordinator: AppCoordinator?
    @Binding var completionPercentage: Double

    var body: some View {
        Group {
            if let store {
                if showingSettings {
                    SettingsView(
                        cameraDeviceManager: cameraDeviceManager,
                        webcamMonitor: webcamMonitor,
                        onSave: {
                            store.refresh()
                            reloadTimerInterval()
                            showingSettings = false
                        },
                        onCancel: {
                            showingSettings = false
                        },
                        onOpenCalibration: {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "calibration")
                        },
                        onCameraChanged: { cameraID in
                            appCoordinator?.restartWebcamWithCamera(cameraID)
                        }
                    )
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
                    .frame(width: 320, height: 300)
            }
        }
        .onAppear {
            if store == nil {
                let s = DailyProgressStore(modelContext: modelContext)
                store = s
                completionPercentage = s.completionPercentage
            }
        }
        .onChange(of: store?.completionPercentage) { _, newValue in
            if let newValue {
                completionPercentage = newValue
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
    @State private var tappedButtonId: Int?
    @State private var showConfetti = false
    @State private var wasGoalReached = false
    @State private var undoToastMl: Int?
    @State private var undoToastTask: Task<Void, Never>?
    @State private var showWeeklyChart = false

    var body: some View {
        VStack(spacing: 16) {
            ProgressRingView(
                fillPercentage: store.completionPercentage,
                currentMl: store.todayTotalMl,
                goalMl: store.goalMl
            )

            if store.isGoalReached {
                goalReachedView
            } else {
                presetButtons
            }

            // Streak
            if store.currentStreak > 0 {
                streakView
            }

            // Weekly chart
            DisclosureGroup(isExpanded: $showWeeklyChart) {
                WeeklyChartView(weeklyData: store.weeklyData, goalMl: store.goalMl)
            } label: {
                Text("Weekly")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if webcamMonitor.status == .denied {
                cameraDeniedView
            } else if webcamMonitor.status == .error || webcamMonitor.status == .interrupted {
                cameraErrorView
            }

            Divider()

            HStack {
                settingsButton
                Spacer()
                quitButton
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            if let ml = undoToastMl {
                undoToast(ml: ml)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: undoToastMl)
        .overlay {
            ConfettiView(isActive: $showConfetti)
        }
        .onChange(of: store.isGoalReached) { _, reached in
            if reached && !wasGoalReached {
                showConfetti = true
            }
            wasGoalReached = reached
        }
        .onAppear {
            wasGoalReached = store.isGoalReached
        }
    }

    // MARK: - Subviews

    private var streakView: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("\(store.currentStreak) day streak")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var presetButtons: some View {
        HStack(spacing: 8) {
            ForEach(store.presetBottleSizes, id: \.self) { sizeMl in
                Button {
                    tappedButtonId = sizeMl
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        // trigger bounce
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        tappedButtonId = nil
                    }
                    logVolume(Double(sizeMl))
                } label: {
                    Text("\(sizeMl)")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .controlSize(.regular)
                .scaleEffect(tappedButtonId == sizeMl ? 1.15 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: tappedButtonId)
            }
        }
    }

    private func undoToast(ml: Int) -> some View {
        HStack(spacing: 8) {
            Text("Logged \(ml) ml")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            Button("Undo") {
                undoToastMl = nil
                undoToastTask?.cancel()
                store.unlogBottle()
                if !store.isGoalReached {
                    reloadTimerInterval()
                    webcamMonitor.start(cameraID: loadSelectedCameraID())
                }
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func logVolume(_ volumeMl: Double) {
        store.logVolume(volumeMl)
        playLogSound()
        showUndoToast(ml: Int(volumeMl))
        if store.isGoalReached {
            timerManager.stop()
            webcamMonitor.stop()
        } else {
            reloadTimerInterval()
        }
    }

    private func showUndoToast(ml: Int) {
        undoToastTask?.cancel()
        undoToastMl = ml
        undoToastTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            undoToastMl = nil
        }
    }

    private func playLogSound() {
        let descriptor = FetchDescriptor<AppSettings>()
        let soundEnabled = (try? store.modelContext.fetch(descriptor).first)?.resolvedSoundEnabled ?? true
        guard soundEnabled else { return }
        NSSound(named: "Pop")?.play()
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
                webcamMonitor.start(cameraID: loadSelectedCameraID())
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

    private var cameraErrorView: some View {
        VStack(spacing: 6) {
            Text(webcamMonitor.errorMessage ?? "Camera error")
                .font(.caption)
                .foregroundStyle(.orange)

            Button("Retry") {
                webcamMonitor.retry()
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

    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit", systemImage: "power")
                .font(.subheadline)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    @MainActor
    private func loadSelectedCameraID() -> String? {
        let descriptor = FetchDescriptor<AppSettings>()
        return try? store.modelContext.fetch(descriptor).first?.selectedCameraID
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
    PopoverContentView(timerManager: DrinkTimerManager(), webcamMonitor: WebcamMonitor(), completionPercentage: .constant(0.5))
        .modelContainer(for: [WaterEntry.self, AppSettings.self], inMemory: true)
}
