import SwiftUI
import SwiftData

struct PopoverContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store: DailyProgressStore?

    var body: some View {
        Group {
            if let store {
                PopoverBody(store: store)
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

    var body: some View {
        VStack(spacing: 16) {
            WaterCupView(fillPercentage: store.completionPercentage)

            progressLabel

            if store.isGoalReached {
                goalReachedView
            } else {
                logButton
            }
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
}

#Preview {
    PopoverContentView()
        .modelContainer(for: [WaterEntry.self, AppSettings.self], inMemory: true)
}
