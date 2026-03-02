import SwiftUI

struct WaterCupView: View {
    /// Fill percentage from 0.0 to 1.0
    var fillPercentage: Double

    @State private var animatedFill: Double = 0

    private let cupWidth: CGFloat = 120
    private let cupHeight: CGFloat = 160
    private let taperRatio: CGFloat = 0.75 // bottom is 75% of top width
    private let strokeWidth: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawCup(context: context, size: size, time: time)
            }
        }
        .frame(width: cupWidth + 20, height: cupHeight + 20)
        .onChange(of: fillPercentage, initial: true) { _, newValue in
            withAnimation(.spring(duration: 0.8, bounce: 0.2)) {
                animatedFill = newValue
            }
        }
    }

    // MARK: - Drawing

    private func drawCup(context: GraphicsContext, size: CGSize, time: Double) {
        let centerX = size.width / 2
        let topY: CGFloat = 10
        let bottomY = topY + cupHeight

        let topHalfWidth = cupWidth / 2
        let bottomHalfWidth = topHalfWidth * taperRatio

        // Cup outline path (trapezoid)
        let cupPath = Path { p in
            p.move(to: CGPoint(x: centerX - topHalfWidth, y: topY))
            p.addLine(to: CGPoint(x: centerX - bottomHalfWidth, y: bottomY))
            p.addLine(to: CGPoint(x: centerX + bottomHalfWidth, y: bottomY))
            p.addLine(to: CGPoint(x: centerX + topHalfWidth, y: topY))
            p.closeSubpath()
        }

        // Clip water fill to cup shape
        if animatedFill > 0 {
            let fillHeight = cupHeight * animatedFill
            let waterTopY = bottomY - fillHeight

            // Water fill with sine wave
            var waterPath = Path()
            let waveAmplitude: CGFloat = animatedFill > 0.02 ? 3.0 : 0
            let waveFrequency: Double = 2.5
            let waveSpeed: Double = 2.0

            // Calculate cup width at water surface level
            let t = fillHeight / cupHeight // 0=bottom, 1=top
            let leftX = centerX - bottomHalfWidth - (topHalfWidth - bottomHalfWidth) * t
            let rightX = centerX + bottomHalfWidth + (topHalfWidth - bottomHalfWidth) * t

            // Start at bottom-left of water
            let cupLeftAtBottom = centerX - bottomHalfWidth
            let cupRightAtBottom = centerX + bottomHalfWidth

            waterPath.move(to: CGPoint(x: cupLeftAtBottom, y: bottomY))

            // Bottom edge
            waterPath.addLine(to: CGPoint(x: cupRightAtBottom, y: bottomY))

            // Right edge up to water level
            waterPath.addLine(to: CGPoint(x: rightX, y: waterTopY))

            // Sine wave across the top of the water
            let steps = 40
            for i in stride(from: steps, through: 0, by: -1) {
                let fraction = CGFloat(i) / CGFloat(steps)
                let x = leftX + (rightX - leftX) * fraction
                let sineValue = sin(Double(fraction) * .pi * 2 * waveFrequency + time * waveSpeed)
                let y = waterTopY + waveAmplitude * CGFloat(sineValue)
                waterPath.addLine(to: CGPoint(x: x, y: y))
            }

            // Close back to bottom-left
            waterPath.addLine(to: CGPoint(x: cupLeftAtBottom, y: bottomY))
            waterPath.closeSubpath()

            // Clip to cup shape and fill
            var clippedContext = context
            clippedContext.clip(to: cupPath)

            let gradient = Gradient(colors: [
                Color(red: 0.3, green: 0.6, blue: 1.0),
                Color(red: 0.15, green: 0.4, blue: 0.9)
            ])
            clippedContext.fill(
                waterPath,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: centerX, y: waterTopY),
                    endPoint: CGPoint(x: centerX, y: bottomY)
                )
            )
        }

        // Draw cup outline on top
        context.stroke(
            cupPath,
            with: .color(.primary.opacity(0.6)),
            lineWidth: strokeWidth
        )
    }
}

#Preview("Empty") {
    WaterCupView(fillPercentage: 0)
        .padding()
}

#Preview("Half Full") {
    WaterCupView(fillPercentage: 0.5)
        .padding()
}

#Preview("Full") {
    WaterCupView(fillPercentage: 1.0)
        .padding()
}
