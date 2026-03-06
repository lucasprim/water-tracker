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
    }

    // MARK: - Subviews

    private var presetButtons: some View {
        HStack(spacing: 8) {
            ForEach(store.presetBottleSizes, id: \.self) { sizeMl in
                Button {
                    logVolume(Double(sizeMl))
                } label: {
                    Text("\(sizeMl)")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .controlSize(.regular)
            }
        }
        .contextMenu {
            Button("Undo Last Entry", role: .destructive) {
                store.unlogBottle()
                if !store.isGoalReached {
                    reloadTimerInterval()
                    webcamMonitor.start(cameraID: loadSelectedCameraID())
                }
            }
            .disabled(store.todayTotalMl <= 0)
        }
    }

    private func logVolume(_ volumeMl: Double) {
        store.logVolume(volumeMl)
        playLogSound()
        if store.isGoalReached {
            timerManager.stop()
            webcamMonitor.stop()
        } else {
            reloadTimerInterval()
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
    PopoverContentView(timerManager: DrinkTimerManager(), webcamMonitor: WebcamMonitor())
        .modelContainer(for: [WaterEntry.self, AppSettings.self], inMemory: true)
}
