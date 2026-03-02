import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var bottleSizeMl: Double = 500
    @State private var dailyGoalMl: Double = 2000
    @State private var drinkIntervalMinutes: Int = 15

    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                bottleSizeSection
                dailyGoalSection
                drinkIntervalSection
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
            Stepper(
                value: $bottleSizeMl,
                in: 100...2000,
                step: 50
            ) {
                Text("\(Int(bottleSizeMl)) ml")
                    .monospacedDigit()
            }
        }
    }

    private var dailyGoalSection: some View {
        Section("Daily Goal") {
            Stepper(
                value: $dailyGoalMl,
                in: 500...10000,
                step: 250
            ) {
                Text("\(Int(dailyGoalMl)) ml")
                    .monospacedDigit()
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
            Stepper(
                value: $drinkIntervalMinutes,
                in: 1...120,
                step: 5
            ) {
                Text("\(drinkIntervalMinutes) min")
                    .monospacedDigit()
            }
        }
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
        }
    }

    private func save() {
        guard isValid else { return }

        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            settings.bottleSizeMl = bottleSizeMl
            settings.dailyGoalMl = dailyGoalMl
            settings.drinkIntervalMinutes = drinkIntervalMinutes
        } else {
            let settings = AppSettings(
                bottleSizeMl: bottleSizeMl,
                dailyGoalMl: dailyGoalMl,
                drinkIntervalMinutes: drinkIntervalMinutes
            )
            modelContext.insert(settings)
        }
        try? modelContext.save()
        onSave?()
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [AppSettings.self, WaterEntry.self], inMemory: true)
}
