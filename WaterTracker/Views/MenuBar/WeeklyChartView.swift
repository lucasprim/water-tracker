import SwiftUI
import Charts

struct WeeklyChartView: View {
    var weeklyData: [DailyTotal]
    var goalMl: Double

    var weeklyAverage: Double {
        guard !weeklyData.isEmpty else { return 0 }
        return weeklyData.reduce(0) { $0 + $1.totalMl } / Double(weeklyData.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("This Week")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Avg: \(Int(weeklyAverage)) ml")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Chart {
                ForEach(weeklyData) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Water", day.totalMl)
                    )
                    .foregroundStyle(barColor(for: day))
                    .cornerRadius(3)
                }

                RuleMark(y: .value("Goal", goalMl))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(.system(.caption2, design: .rounded))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let ml = value.as(Double.self) {
                            Text("\(Int(ml / 1000))L")
                                .font(.system(.caption2, design: .rounded))
                        }
                    }
                }
            }
            .frame(height: 100)
        }
    }

    private func barColor(for day: DailyTotal) -> Color {
        if day.totalMl >= goalMl {
            return .green
        } else if day.totalMl > 0 {
            return .blue
        } else {
            return .gray.opacity(0.3)
        }
    }
}
