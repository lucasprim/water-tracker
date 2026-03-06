import SwiftUI

struct ProgressRingView: View {
    var fillPercentage: Double
    var currentMl: Double
    var goalMl: Double

    @State private var animatedFill: Double = 0

    private let ringDiameter: CGFloat = 160
    private let lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

            // Wave fill inside ring
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                WaveFillShape(fillLevel: animatedFill, time: time)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.45, green: 0.75, blue: 1.0).opacity(0.35),
                                Color(red: 0.22, green: 0.52, blue: 0.95).opacity(0.45)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(Circle().inset(by: lineWidth / 2))
            }

            // Gradient fill ring
            Circle()
                .trim(from: 0, to: animatedFill)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.45, green: 0.75, blue: 1.0),
                            Color(red: 0.22, green: 0.52, blue: 0.95),
                            Color(red: 0.15, green: 0.40, blue: 0.88)
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * animatedFill)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center text
            VStack(spacing: 2) {
                Text(formatMl(Int(currentMl)))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())

                Text("/ \(formatMl(Int(goalMl))) ml")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .onChange(of: fillPercentage, initial: true) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animatedFill = newValue
            }
        }
    }

    private func formatMl(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Wave Fill Shape

private struct WaveFillShape: Shape {
    var fillLevel: Double
    var time: Double

    var animatableData: Double {
        get { fillLevel }
        set { fillLevel = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard fillLevel > 0 else { return Path() }

        let waterTopY = rect.height * (1.0 - fillLevel)
        let waveAmplitude: CGFloat = fillLevel > 0.02 ? 3.0 : 0

        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))

        // Right edge up to water line
        path.addLine(to: CGPoint(x: rect.width, y: waterTopY))

        // Wave surface from right to left
        let steps = 60
        for i in stride(from: steps, through: 0, by: -1) {
            let fraction = CGFloat(i) / CGFloat(steps)
            let x = rect.width * fraction
            let wave1 = sin(Double(fraction) * .pi * 2 * 2.0 + time * 1.5)
            let wave2 = sin(Double(fraction) * .pi * 2 * 1.3 + time * 1.05 + 1.0)
            let combined = (wave1 + wave2 * 0.4) / 1.4
            let y = waterTopY + waveAmplitude * CGFloat(combined)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.closeSubpath()
        return path
    }
}

#Preview("Empty") {
    ProgressRingView(fillPercentage: 0, currentMl: 0, goalMl: 2000)
        .padding()
}

#Preview("Quarter") {
    ProgressRingView(fillPercentage: 0.25, currentMl: 500, goalMl: 2000)
        .padding()
}

#Preview("Half") {
    ProgressRingView(fillPercentage: 0.5, currentMl: 1000, goalMl: 2000)
        .padding()
}

#Preview("Full") {
    ProgressRingView(fillPercentage: 1.0, currentMl: 2000, goalMl: 2000)
        .padding()
}
