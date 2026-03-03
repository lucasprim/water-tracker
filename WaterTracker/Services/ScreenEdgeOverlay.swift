import AppKit
import SwiftUI

@MainActor
final class ScreenEdgeOverlay {
    static let shared = ScreenEdgeOverlay()

    private(set) var isShowing = false
    private var window: NSPanel?
    private var pulseTask: Task<Void, Never>?

    private let fadeInDuration: TimeInterval = 0.4
    private let fadeOutDuration: TimeInterval = 0.6
    private let pauseBetweenPulses: TimeInterval = 0.3

    private init() {}

    func flash() {
        guard !isShowing else { return }
        guard let screen = NSScreen.main else { return }

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: EdgeGradientView())
        panel.alphaValue = 0

        self.window = panel
        self.isShowing = true

        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()

        pulseTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.animateAlpha(to: 1, duration: self?.fadeInDuration ?? 0.4)
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { break }
                await self?.animateAlpha(to: 0.15, duration: self?.fadeOutDuration ?? 0.6)
                try? await Task.sleep(for: .milliseconds(Int(( self?.pauseBetweenPulses ?? 0.3) * 1000)))
            }
        }
    }

    func dismiss() {
        pulseTask?.cancel()
        pulseTask = nil

        guard let window else {
            isShowing = false
            return
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.cleanup()
        }
    }

    private func animateAlpha(to value: CGFloat, duration: TimeInterval) async {
        guard let window else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = value
            } completionHandler: {
                cont.resume()
            }
        }
    }

    private func cleanup() {
        window?.orderOut(nil)
        window = nil
        isShowing = false
    }
}

// MARK: - SwiftUI Gradient View

private struct EdgeGradientView: View {
    private let edgeSize: CGFloat = 100
    private let edgeColor = Color.blue.opacity(0.45)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Top edge
                LinearGradient(
                    colors: [edgeColor, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: edgeSize)
                .frame(maxHeight: .infinity, alignment: .top)

                // Bottom edge
                LinearGradient(
                    colors: [edgeColor, .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: edgeSize)
                .frame(maxHeight: .infinity, alignment: .bottom)

                // Left edge
                LinearGradient(
                    colors: [edgeColor, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: edgeSize)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right edge
                LinearGradient(
                    colors: [edgeColor, .clear],
                    startPoint: .trailing,
                    endPoint: .leading
                )
                .frame(width: edgeSize)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}
