import CoreVideo
import CoreGraphics

// MARK: - Algorithm ID

enum DetectionAlgorithmID: String, Codable, CaseIterable {
    case colorFingers

    var displayName: String {
        switch self {
        case .colorFingers: return "Color + Fingers"
        }
    }

    var description: String {
        switch self {
        case .colorFingers:
            return "Detects drinking by checking for hand joints near your face combined with bottle color matching. Requires color calibration."
        }
    }
}

// MARK: - Detection Input

struct DetectionInput: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let faceBox: CGRect
    let faceArea: CGFloat
    let faceCenter: CGPoint
    let handPoints: [CGPoint]
    let drinkObjects: [(center: CGPoint, confidence: Float, label: String)]
}

// MARK: - Calibration Data

struct CalibrationData: Sendable {
    let baseline: CGFloat
    let dropThreshold: CGFloat
    let bottleHue: CGFloat?
    let bottleSaturation: CGFloat?
    let bottleHueTolerance: CGFloat
    let bottleSatTolerance: CGFloat
}

// MARK: - Detection Result

struct DetectionResult: Sendable {
    let isDrinking: Bool
    let logEntry: String
}

// MARK: - Protocol

protocol DetectionAlgorithm: Sendable {
    static var id: DetectionAlgorithmID { get }
    func analyze(input: DetectionInput, calibration: CalibrationData) -> DetectionResult
    func computeTestingSignals(input: DetectionInput, calibration: CalibrationData) -> DetectionSignals
}

// MARK: - Factory

func makeDetectionAlgorithm(for id: DetectionAlgorithmID) -> any DetectionAlgorithm {
    switch id {
    case .colorFingers: return ColorFingersAlgorithm()
    }
}

// MARK: - Shared Utilities

/// Convert RGB (0-1) to HSV (h: 0-360, s: 0-1, v: 0-1).
func rgbToHSV(r: CGFloat, g: CGFloat, b: CGFloat) -> (h: CGFloat, s: CGFloat, v: CGFloat) {
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

/// Extract the dominant non-skin color from the area around a face (wide sampling for calibration/preview).
func extractDominantNonSkinColor(
    pixelBuffer: CVPixelBuffer,
    faceBox: CGRect
) -> (hue: CGFloat, saturation: CGFloat)? {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

    let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

    let expandedBox = faceBox.insetBy(dx: -faceBox.width * 0.5, dy: -faceBox.height * 0.5)
    let minX = max(0, Int(expandedBox.minX * CGFloat(width)))
    let maxX = min(width - 1, Int(expandedBox.maxX * CGFloat(width)))
    let minY = max(0, Int((1.0 - expandedBox.maxY) * CGFloat(height)))
    let maxY = min(height - 1, Int((1.0 - expandedBox.minY) * CGFloat(height)))

    var nonSkinHues: [(hue: CGFloat, saturation: CGFloat)] = []
    let step = 6

    for y in stride(from: minY, to: maxY, by: step) {
        for x in stride(from: minX, to: maxX, by: step) {
            let offset = y * bytesPerRow + x * 4
            let b = CGFloat(buffer[offset]) / 255.0
            let g = CGFloat(buffer[offset + 1]) / 255.0
            let r = CGFloat(buffer[offset + 2]) / 255.0

            let (h, s, v) = rgbToHSV(r: r, g: g, b: b)

            guard s > 0.20 && v > 0.20 else { continue }
            guard h > 55 && h < 340 else { continue }

            nonSkinHues.append((hue: h, saturation: s))
        }
    }

    guard nonSkinHues.count >= 5 else { return nil }

    let sortedH = nonSkinHues.map(\.hue).sorted()
    let sortedS = nonSkinHues.map(\.saturation).sorted()
    return (hue: sortedH[sortedH.count / 2], saturation: sortedS[sortedS.count / 2])
}
