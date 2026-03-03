import SwiftUI

struct CameraFrameView: View {
    let image: CGImage?
    var overlay: FrameOverlay?
    var showOverlays = true
    /// Called when user taps on the image; returns (SwiftUI Color, hue 0-360, saturation 0-1)
    var onTapColor: ((Color, Float, Float) -> Void)?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            handleTap(at: location, in: geo.size, cgImage: image)
                        }

                    if showOverlays, let overlay {
                        overlayCanvas(overlay: overlay, imageSize: CGSize(width: image.width, height: image.height), viewSize: geo.size)
                    }
                } else {
                    Rectangle()
                        .fill(.black.opacity(0.3))
                    Text("No camera feed")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Overlay Drawing

    private func overlayCanvas(overlay: FrameOverlay, imageSize: CGSize, viewSize: CGSize) -> some View {
        let fitting = fitRect(imageSize: imageSize, viewSize: viewSize)
        return Canvas { context, _ in
            // Face bounding box (green)
            if let faceBox = overlay.faceBox {
                let rect = visionRectToView(faceBox, fitting: fitting)
                context.stroke(Path(rect), with: .color(.green), lineWidth: 2)
                context.draw(Text("Face").font(.caption2).foregroundStyle(.green),
                             at: CGPoint(x: rect.midX, y: rect.minY - 8))
            }

            // Hand points (yellow dots)
            for point in overlay.handPoints {
                let viewPoint = visionPointToView(point, fitting: fitting)
                let dotRect = CGRect(x: viewPoint.x - 3, y: viewPoint.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: dotRect), with: .color(.yellow))
            }

            // Object detections (blue rects)
            for detection in overlay.objectDetections {
                let rect = visionRectToView(detection.box, fitting: fitting)
                context.stroke(Path(rect), with: .color(.blue), lineWidth: 2)
                let label = "\(detection.label) \(Int(detection.confidence * 100))%"
                context.draw(Text(label).font(.caption2).foregroundStyle(.blue),
                             at: CGPoint(x: rect.midX, y: rect.minY - 8))
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .allowsHitTesting(false)
    }

    // MARK: - Coordinate Conversion

    /// Returns (origin, size) of the fitted image within the view
    private func fitRect(imageSize: CGSize, viewSize: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        var fitSize: CGSize
        if imageAspect > viewAspect {
            fitSize = CGSize(width: viewSize.width, height: viewSize.width / imageAspect)
        } else {
            fitSize = CGSize(width: viewSize.height * imageAspect, height: viewSize.height)
        }
        let origin = CGPoint(
            x: (viewSize.width - fitSize.width) / 2,
            y: (viewSize.height - fitSize.height) / 2
        )
        return CGRect(origin: origin, size: fitSize)
    }

    /// Convert Vision normalized rect (bottom-left origin) to view coordinates (top-left origin)
    private func visionRectToView(_ visionRect: CGRect, fitting: CGRect) -> CGRect {
        let x = fitting.origin.x + visionRect.minX * fitting.width
        let y = fitting.origin.y + (1.0 - visionRect.maxY) * fitting.height
        let w = visionRect.width * fitting.width
        let h = visionRect.height * fitting.height
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Convert Vision normalized point (bottom-left origin) to view coordinates
    private func visionPointToView(_ point: CGPoint, fitting: CGRect) -> CGPoint {
        CGPoint(
            x: fitting.origin.x + point.x * fitting.width,
            y: fitting.origin.y + (1.0 - point.y) * fitting.height
        )
    }

    // MARK: - Tap to Pick Color

    private func handleTap(at location: CGPoint, in viewSize: CGSize, cgImage: CGImage) {
        guard onTapColor != nil else { return }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let fitting = fitRect(imageSize: imageSize, viewSize: viewSize)

        // Convert tap location to image pixel coordinates
        let relX = (location.x - fitting.origin.x) / fitting.width
        let relY = (location.y - fitting.origin.y) / fitting.height
        guard relX >= 0, relX <= 1, relY >= 0, relY <= 1 else { return }

        let pixelX = Int(relX * CGFloat(cgImage.width))
        let pixelY = Int(relY * CGFloat(cgImage.height))
        guard pixelX >= 0, pixelX < cgImage.width, pixelY >= 0, pixelY < cgImage.height else { return }

        // Sample the pixel color
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else { return }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        let offset = pixelY * bytesPerRow + pixelX * bytesPerPixel

        // Handle both BGRA and RGBA
        let r, g, b: CGFloat
        if cgImage.bitmapInfo.contains(.byteOrder32Little) {
            // BGRA
            b = CGFloat(ptr[offset]) / 255.0
            g = CGFloat(ptr[offset + 1]) / 255.0
            r = CGFloat(ptr[offset + 2]) / 255.0
        } else {
            // RGBA
            r = CGFloat(ptr[offset]) / 255.0
            g = CGFloat(ptr[offset + 1]) / 255.0
            b = CGFloat(ptr[offset + 2]) / 255.0
        }

        let (h, s, _) = rgbToHSV(r: r, g: g, b: b)
        let color = Color(red: r, green: g, blue: b)
        onTapColor?(color, Float(h), Float(s))
    }

    private func rgbToHSV(r: CGFloat, g: CGFloat, b: CGFloat) -> (h: CGFloat, s: CGFloat, v: CGFloat) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        let v = maxC
        let s: CGFloat = maxC == 0 ? 0 : delta / maxC

        var h: CGFloat = 0
        if delta > 0 {
            if maxC == r {
                h = 60.0 * fmod((g - b) / delta, 6.0)
            } else if maxC == g {
                h = 60.0 * ((b - r) / delta + 2.0)
            } else {
                h = 60.0 * ((r - g) / delta + 4.0)
            }
            if h < 0 { h += 360.0 }
        }

        return (h, s, v)
    }
}
