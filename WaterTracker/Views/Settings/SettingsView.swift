import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var bottleSizeMl: Double = 500
    @State private var dailyGoalMl: Double = 2000
    @State private var drinkIntervalMinutes: Int = 15
    @State private var selectedCameraID: String?

    var cameraDeviceManager: CameraDeviceManager?
    var webcamMonitor: WebcamMonitor?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    var onOpenCalibration: (() -> Void)?
    var onCameraChanged: ((String?) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                bottleSizeSection
                dailyGoalSection
                drinkIntervalSection
                if let cameraDeviceManager {
                    cameraSection(cameraDeviceManager)
                }
                if let webcamMonitor {
                    webcamDetectionSection(webcamMonitor)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            footer
        }
        .frame(width: 280)
        .onAppear(perform: loadSettings)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Button("Cancel") { onCancel?() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Settings")
                .font(.headline)
            Spacer()
            Button("Save", action: save)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .disabled(!isValid)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var bottleSizeSection: some View {
        Section("Bottle Size") {
            HStack {
                TextField("ml", value: $bottleSizeMl, format: .number)
                    .monospacedDigit()
                    .textFieldStyle(.roundedBorder)
                Text("ml")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dailyGoalSection: some View {
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
    }

    private var drinkIntervalSection: some View {
        Section("Drink Reminder") {
            HStack {
                TextField("min", value: $drinkIntervalMinutes, format: .number)
                    .monospacedDigit()
                    .textFieldStyle(.roundedBorder)
                Text("min")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func cameraSection(_ manager: CameraDeviceManager) -> some View {
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
        }
    }

    private func webcamDetectionSection(_ monitor: WebcamMonitor) -> some View {
        Section("Webcam Detection") {
            Button("Open Calibration...") {
                onOpenCalibration?()
            }
            detectionLogView(monitor)
        }
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

    private var footer: some View {
        Text("Reminder interval resets each time you drink")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.bottom, 16)
    }

    // MARK: - Validation

    private var isValid: Bool {
        bottleSizeMl > 0 && dailyGoalMl >= bottleSizeMl && drinkIntervalMinutes >= 1
    }

    // MARK: - Persistence

    private func loadSettings() {
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            bottleSizeMl = settings.bottleSizeMl
            dailyGoalMl = settings.dailyGoalMl
            drinkIntervalMinutes = settings.drinkIntervalMinutes
            selectedCameraID = settings.selectedCameraID
        }
    }

    private func save() {
        guard isValid else { return }

        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            settings.bottleSizeMl = bottleSizeMl
            settings.dailyGoalMl = dailyGoalMl
            settings.drinkIntervalMinutes = drinkIntervalMinutes
            settings.selectedCameraID = selectedCameraID
        } else {
            let settings = AppSettings(
                bottleSizeMl: bottleSizeMl,
                dailyGoalMl: dailyGoalMl,
                drinkIntervalMinutes: drinkIntervalMinutes
            )
            settings.selectedCameraID = selectedCameraID
            modelContext.insert(settings)
        }
        try? modelContext.save()
        onCameraChanged?(selectedCameraID)
        onSave?()
    }

}

#Preview {
    SettingsView()
        .modelContainer(for: [AppSettings.self, WaterEntry.self], inMemory: true)
}
