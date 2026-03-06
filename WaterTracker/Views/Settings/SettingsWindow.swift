import SwiftUI
import SwiftData

struct SettingsWindow: View {
    var cameraDeviceManager: CameraDeviceManager?
    var webcamMonitor: WebcamMonitor?
    var onCameraChanged: ((String?) -> Void)?
    var onSettingsSaved: (() -> Void)?

    var body: some View {
        TabView {
            GeneralTab(onSettingsSaved: onSettingsSaved)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            GoalBottlesTab(onSettingsSaved: onSettingsSaved)
                .tabItem {
                    Label("Goal & Bottles", systemImage: "drop.fill")
                }

            RemindersTab(onSettingsSaved: onSettingsSaved)
                .tabItem {
                    Label("Reminders", systemImage: "bell")
                }

            CameraTab(
                cameraDeviceManager: cameraDeviceManager,
                webcamMonitor: webcamMonitor,
                onCameraChanged: onCameraChanged,
                onSettingsSaved: onSettingsSaved
            )
            .tabItem {
                Label("Camera", systemImage: "camera")
            }
        }
        .frame(width: 420, height: 340)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                NSApp.windows.first { $0.title.contains("Settings") || $0.identifier?.rawValue == "settings" }?.center()
            }
        }
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var soundEnabled = true
    var onSettingsSaved: (() -> Void)?

    var body: some View {
        Form {
            Section("Feedback") {
                Toggle("Play sound on log", isOn: $soundEnabled)
                    .onChange(of: soundEnabled) { _, newValue in
                        saveField { $0.soundEnabled = newValue }
                    }
            }

            Section("Keyboard Shortcut") {
                HStack {
                    Text("Quick-log")
                    Spacer()
                    Text("Ctrl + Shift + W")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
    }

    private func loadSettings() {
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            soundEnabled = settings.resolvedSoundEnabled
        }
    }

    private func saveField(_ update: (AppSettings) -> Void) {
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            update(settings)
            try? modelContext.save()
            onSettingsSaved?()
        }
    }
}

// MARK: - Goal & Bottles Tab

private struct GoalBottlesTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var bottleSizeMl: Double = 500
    @State private var dailyGoalMl: Double = 2000
    @State private var presetSizesText: String = "250, 350, 500, 750"
    var onSettingsSaved: (() -> Void)?

    var body: some View {
        Form {
            Section("Default Bottle Size") {
                HStack {
                    TextField("ml", value: $bottleSizeMl, format: .number)
                        .monospacedDigit()
                        .textFieldStyle(.roundedBorder)
                    Text("ml")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Daily Goal") {
                HStack {
                    TextField("ml", value: $dailyGoalMl, format: .number)
                        .monospacedDigit()
                        .textFieldStyle(.roundedBorder)
                    Text("ml")
                        .foregroundStyle(.secondary)
                }
                if dailyGoalMl < bottleSizeMl {
                    Text("Goal should be at least one bottle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Preset Quick-Log Sizes") {
                TextField("Comma-separated ml values", text: $presetSizesText)
                    .textFieldStyle(.roundedBorder)
                Text("e.g. 250, 350, 500, 750")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
    }

    private var isValid: Bool {
        bottleSizeMl > 0 && dailyGoalMl >= bottleSizeMl
    }

    private func loadSettings() {
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            bottleSizeMl = settings.bottleSizeMl
            dailyGoalMl = settings.dailyGoalMl
            let sizes = settings.resolvedPresetBottleSizes
            presetSizesText = sizes.map { String($0) }.joined(separator: ", ")
        }
    }

    private func save() {
        guard isValid else { return }
        let parsedSizes = presetSizesText
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 }

        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            settings.bottleSizeMl = bottleSizeMl
            settings.dailyGoalMl = dailyGoalMl
            if !parsedSizes.isEmpty {
                settings.presetBottleSizes = parsedSizes
            }
            try? modelContext.save()
            onSettingsSaved?()
        }
    }
}

// MARK: - Reminders Tab

private struct RemindersTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var drinkIntervalMinutes: Int = 15
    var onSettingsSaved: (() -> Void)?

    var body: some View {
        Form {
            Section("Drink Reminder Interval") {
                HStack {
                    TextField("min", value: $drinkIntervalMinutes, format: .number)
                        .monospacedDigit()
                        .textFieldStyle(.roundedBorder)
                    Text("minutes")
                        .foregroundStyle(.secondary)
                }
                Text("Reminder interval resets each time you drink")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(drinkIntervalMinutes < 1)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
    }

    private func loadSettings() {
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            drinkIntervalMinutes = settings.drinkIntervalMinutes
        }
    }

    private func save() {
        guard drinkIntervalMinutes >= 1 else { return }
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            settings.drinkIntervalMinutes = drinkIntervalMinutes
            try? modelContext.save()
            onSettingsSaved?()
        }
    }
}

// MARK: - Camera Tab

private struct CameraTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @State private var selectedCameraID: String?
    var cameraDeviceManager: CameraDeviceManager?
    var webcamMonitor: WebcamMonitor?
    var onCameraChanged: ((String?) -> Void)?
    var onSettingsSaved: (() -> Void)?

    var body: some View {
        Form {
            if let manager = cameraDeviceManager {
                Section("Camera") {
                    Picker("Camera", selection: $selectedCameraID) {
                        Text("Default")
                            .tag(nil as String?)
                        ForEach(manager.availableDevices, id: \.uniqueID) { device in
                            Text(device.localizedName)
                                .tag(device.uniqueID as String?)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedCameraID) { _, newValue in
                        saveCamera(newValue)
                    }
                }
            }

            Section("Calibration") {
                Button("Open Calibration...") {
                    openWindow(id: "calibration")
                }
            }

            if let monitor = webcamMonitor {
                Section("Detection Log") {
                    detectionLogView(monitor)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
    }

    private func detectionLogView(_ monitor: WebcamMonitor) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(monitor.detectionLog.suffix(30).enumerated()), id: \.offset) { _, entry in
                    Text(entry)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(logEntryColor(entry))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 120)
        .defaultScrollAnchor(.bottom)
    }

    private func logEntryColor(_ entry: String) -> Color {
        if entry.contains("TRIGGERED") { return .red }
        if entry.contains("DRINK(bottle") { return .green }
        if entry.contains("DRINK(hand") || entry.contains("DRINK(occluded") { return .orange }
        return .secondary
    }

    private func loadSettings() {
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            selectedCameraID = settings.selectedCameraID
        }
    }

    private func saveCamera(_ cameraID: String?) {
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            settings.selectedCameraID = cameraID
            try? modelContext.save()
            onCameraChanged?(cameraID)
            onSettingsSaved?()
        }
    }
}
