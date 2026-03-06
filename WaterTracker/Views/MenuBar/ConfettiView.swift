import SwiftUI

struct ConfettiView: View {
    @Binding var isActive: Bool
    @State private var particles: [ConfettiParticle] = []
    @State private var startTime: Date = .now

    private let colors: [Color] = [
        .blue, .cyan, .green, .yellow, .orange, .pink, .purple
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startTime)
                for particle in particles {
                    let age = elapsed - particle.delay
                    guard age > 0 else { continue }

                    let x = particle.startX * size.width + particle.driftX * CGFloat(age)
                    let y = particle.startY + particle.velocityY * CGFloat(age) + 200 * CGFloat(age * age)
                    let opacity = max(0, 1.0 - age / 2.0)
                    let rotation = Angle.degrees(particle.spin * age)

                    guard opacity > 0, y < size.height + 20 else { continue }

                    var ctx = context
                    ctx.opacity = opacity
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: rotation)

                    let rect = CGRect(
                        x: -particle.width / 2,
                        y: -particle.height / 2,
                        width: particle.width,
                        height: particle.height
                    )
                    ctx.fill(Path(rect), with: .color(particle.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, active in
            if active {
                spawnParticles()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    isActive = false
                    particles = []
                }
            }
        }
    }

    private func spawnParticles() {
        startTime = .now
        particles = (0..<40).map { _ in
            ConfettiParticle(
                startX: CGFloat.random(in: 0.1...0.9),
                startY: CGFloat.random(in: -30 ... -5),
                velocityY: CGFloat.random(in: 20...80),
                driftX: CGFloat.random(in: -40...40),
                spin: Double.random(in: 100...400) * (Bool.random() ? 1 : -1),
                delay: Double.random(in: 0...0.3),
                width: CGFloat.random(in: 4...8),
                height: CGFloat.random(in: 6...12),
                color: colors.randomElement()!
            )
        }
    }
}

private struct ConfettiParticle {
    let startX: CGFloat
    let startY: CGFloat
    let velocityY: CGFloat
    let driftX: CGFloat
    let spin: Double
    let delay: Double
    let width: CGFloat
    let height: CGFloat
    let color: Color
}
