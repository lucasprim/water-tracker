import SwiftUI

struct WaterCupView: View {
    /// Fill percentage from 0.0 to 1.0
    var fillPercentage: Double

    @State private var animatedFill: Double = 0

    private let cupWidth: CGFloat = 120
    private let cupHeight: CGFloat = 160
    private let taperRatio: CGFloat = 0.72
    private let strokeWidth: CGFloat = 2.5
    private let cornerRadius: CGFloat = 6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawCup(context: context, size: size, time: time)
            }
        }
        .frame(width: cupWidth + 20, height: cupHeight + 20)
        .onChange(of: fillPercentage, initial: true) { _, newValue in
            withAnimation(.spring(duration: 0.6, bounce: 0.15)) {
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

        // Cup outline path (rounded trapezoid)
        let cupPath = Path { p in
            let tl = CGPoint(x: centerX - topHalfWidth, y: topY)
            let bl = CGPoint(x: centerX - bottomHalfWidth, y: bottomY)
            let br = CGPoint(x: centerX + bottomHalfWidth, y: bottomY)
            let tr = CGPoint(x: centerX + topHalfWidth, y: topY)

            p.move(to: tl)
            p.addLine(to: CGPoint(x: bl.x + cornerRadius, y: bl.y))
            p.addQuadCurve(to: CGPoint(x: bl.x, y: bl.y - cornerRadius), control: bl)
            p.addLine(to: tl)
            p.closeSubpath()

            p.move(to: tl)
            p.addLine(to: CGPoint(x: bl.x, y: bl.y - cornerRadius))
            p.addQuadCurve(to: CGPoint(x: bl.x + cornerRadius, y: bl.y), control: bl)
            p.addLine(to: CGPoint(x: br.x - cornerRadius, y: br.y))
            p.addQuadCurve(to: CGPoint(x: br.x, y: br.y - cornerRadius), control: br)
            p.addLine(to: tr)
            p.closeSubpath()
        }

        // Simpler cup path for clipping (no gaps from rounded corners)
        let clipPath = Path { p in
            p.move(to: CGPoint(x: centerX - topHalfWidth, y: topY))
            p.addLine(to: CGPoint(x: centerX - bottomHalfWidth, y: bottomY))
            p.addLine(to: CGPoint(x: centerX + bottomHalfWidth, y: bottomY))
            p.addLine(to: CGPoint(x: centerX + topHalfWidth, y: topY))
            p.closeSubpath()
        }

        // Water fill
        if animatedFill > 0 {
            let fillHeight = cupHeight * animatedFill
            let waterTopY = bottomY - fillHeight

            var waterPath = Path()

            // Gentle sloshing wave
            let waveAmplitude: CGFloat = animatedFill > 0.02 ? 2.5 : 0
            let waveFrequency: Double = 2.0
            let waveSpeed: Double = 1.5

            // Cup width at water surface
            let t = fillHeight / cupHeight
            let leftX = centerX - bottomHalfWidth - (topHalfWidth - bottomHalfWidth) * t
            let rightX = centerX + bottomHalfWidth + (topHalfWidth - bottomHalfWidth) * t

            let cupLeftAtBottom = centerX - bottomHalfWidth
            let cupRightAtBottom = centerX + bottomHalfWidth

            waterPath.move(to: CGPoint(x: cupLeftAtBottom, y: bottomY))
            waterPath.addLine(to: CGPoint(x: cupRightAtBottom, y: bottomY))
            waterPath.addLine(to: CGPoint(x: rightX, y: waterTopY))

            // Sine wave surface
            let steps = 50
            for i in stride(from: steps, through: 0, by: -1) {
                let fraction = CGFloat(i) / CGFloat(steps)
                let x = leftX + (rightX - leftX) * fraction
                let wave1 = sin(Double(fraction) * .pi * 2 * waveFrequency + time * waveSpeed)
                let wave2 = sin(Double(fraction) * .pi * 2 * 1.3 + time * waveSpeed * 0.7 + 1.0)
                let combined = (wave1 + wave2 * 0.4) / 1.4
                let y = waterTopY + waveAmplitude * CGFloat(combined)
                waterPath.addLine(to: CGPoint(x: x, y: y))
            }

            waterPath.addLine(to: CGPoint(x: cupLeftAtBottom, y: bottomY))
            waterPath.closeSubpath()

            // Clip to cup and fill with gradient
            var clippedContext = context
            clippedContext.clip(to: clipPath)

            let gradient = Gradient(colors: [
                Color(red: 0.38, green: 0.68, blue: 1.0),
                Color(red: 0.22, green: 0.52, blue: 0.95),
                Color(red: 0.15, green: 0.40, blue: 0.88)
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

        // Cup outline stroke
        let outlinePath = Path { p in
            let tl = CGPoint(x: centerX - topHalfWidth, y: topY)
            let bl = CGPoint(x: centerX - bottomHalfWidth, y: bottomY)
            let br = CGPoint(x: centerX + bottomHalfWidth, y: bottomY)
            let tr = CGPoint(x: centerX + topHalfWidth, y: topY)

            p.move(to: tl)
            p.addLine(to: CGPoint(x: bl.x, y: bl.y - cornerRadius))
            p.addQuadCurve(to: CGPoint(x: bl.x + cornerRadius, y: bl.y), control: bl)
            p.addLine(to: CGPoint(x: br.x - cornerRadius, y: br.y))
            p.addQuadCurve(to: CGPoint(x: br.x, y: br.y - cornerRadius), control: br)
            p.addLine(to: tr)
        }

        context.stroke(
            outlinePath,
            with: .color(.primary.opacity(0.5)),
            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
        )
    }
}

#Preview("Empty") {
    WaterCupView(fillPercentage: 0)
        .padding()
}

#Preview("Quarter") {
    WaterCupView(fillPercentage: 0.25)
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
