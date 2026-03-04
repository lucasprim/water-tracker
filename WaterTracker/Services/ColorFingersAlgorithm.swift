import CoreVideo
import CoreGraphics

struct ColorFingersAlgorithm: DetectionAlgorithm {
    static let id: DetectionAlgorithmID = .colorFingers

    func analyze(input: DetectionInput, calibration: CalibrationData) -> DetectionResult {
        let faceBox = input.faceBox
        let faceArea = input.faceArea
        let faceCenter = input.faceCenter
        let handNearFace = isAnyHandPointNearFace(handPoints: input.handPoints, faceBox: faceBox)
        let baseline = calibration.baseline
        let hasBottleColor = calibration.bottleHue != nil

        let colorTag = hasBottleColor ? "C" : "-"
        let log = String(format: "F=(%.2f,%.2f,%.2f,%.2f) H=%d O=%d %@ base=%.3f",
                         faceBox.minX, faceBox.minY, faceBox.width, faceBox.height,
                         input.handPoints.count, input.drinkObjects.count, colorTag, baseline)

        // Strong trigger: drink object detected near face and above midframe
        for obj in input.drinkObjects {
            if obj.center.y > 0.35
                && isObjectNearFace(objectCenter: obj.center, faceCenter: faceCenter, faceBox: faceBox) {
                let triggerLog = String(format: "DRINK(bottle@face) obj=(%.2f,%.2f) conf=%.2f",
                                        obj.center.x, obj.center.y, obj.confidence)
                return DetectionResult(isDrinking: true, logEntry: triggerLog)
            }
        }

        // Moderate trigger: hand near face + confirmation signal
        if handNearFace {
            if hasBottleColor {
                let colorPresent = isBottleColorPresent(pixelBuffer: input.pixelBuffer, faceBox: faceBox, calibration: calibration)
                if colorPresent {
                    let handPos = input.handPoints.first ?? .zero
                    let triggerLog = String(format: "DRINK(hand+color) H@(%.2f,%.2f)",
                                            handPos.x, handPos.y)
                    return DetectionResult(isDrinking: true, logEntry: triggerLog)
                }
            } else if baseline > 0 {
                let dropRatio = 1.0 - (faceArea / baseline)
                if dropRatio > 0.30 {
                    let handPos = input.handPoints.first ?? .zero
                    let triggerLog = String(format: "DRINK(hand+occ) area=%.3f drop=%.0f%% H@(%.2f,%.2f)",
                                            faceArea, dropRatio * 100, handPos.x, handPos.y)
                    return DetectionResult(isDrinking: true, logEntry: triggerLog)
                }
            }
        }

        return DetectionResult(isDrinking: false, logEntry: log)
    }

    func computeTestingSignals(input: DetectionInput, calibration: CalibrationData) -> DetectionSignals {
        let faceBox = input.faceBox
        let faceArea = Float(input.faceArea)
        let faceCenter = input.faceCenter
        let handNearFace = isAnyHandPointNearFace(handPoints: input.handPoints, faceBox: faceBox)
        let colorRatio = Float(bottleColorMatchRatio(pixelBuffer: input.pixelBuffer, faceBox: faceBox, calibration: calibration))
        let mask = generateColorMatchMask(pixelBuffer: input.pixelBuffer, faceBox: faceBox, calibration: calibration)

        var objectNearFace = false
        var objectLabel: String?
        var objectConfidence: Float = 0
        for obj in input.drinkObjects {
            if obj.center.y > 0.35
                && isObjectNearFace(objectCenter: obj.center, faceCenter: faceCenter, faceBox: faceBox) {
                objectNearFace = true
                objectLabel = obj.label
                objectConfidence = obj.confidence
                break
            }
        }

        var isDrinking = false
        var triggerReason: String?

        if objectNearFace {
            isDrinking = true
            triggerReason = "Object near face (\(objectLabel ?? "?"))"
        } else if handNearFace {
            if calibration.bottleHue != nil && colorRatio > 0.05 {
                isDrinking = true
                triggerReason = "Hand + color match (\(Int(colorRatio * 100))%)"
            } else if calibration.bottleHue == nil, calibration.baseline > 0 {
                let dropRatio = 1.0 - (CGFloat(faceArea) / calibration.baseline)
                if dropRatio > 0.30 {
                    isDrinking = true
                    triggerReason = "Hand + face occlusion (\(Int(dropRatio * 100))%)"
                }
            }
        }

        return DetectionSignals(
            faceDetected: true, faceArea: faceArea, baseline: Float(calibration.baseline),
            handNearFace: handNearFace, colorMatchRatio: colorRatio, colorMatchThreshold: 0.05,
            objectNearFace: objectNearFace, objectLabel: objectLabel, objectConfidence: objectConfidence,
            isDrinking: isDrinking, triggerReason: triggerReason, colorMatchMask: mask
        )
    }

    // MARK: - Private Helpers

    /// Vertical strip around face: narrow horizontal (25% wider than face), tall vertical (1.5x face height above & below).
    private func colorSamplingRegion(faceBox: CGRect) -> CGRect {
        CGRect(
            x: faceBox.minX - faceBox.width * 0.125,
            y: faceBox.minY - faceBox.height * 1.5,
            width: faceBox.width * 1.25,
            height: faceBox.height * 4.0
        )
    }

    private func bottleColorMatchRatio(pixelBuffer: CVPixelBuffer, faceBox: CGRect, calibration: CalibrationData) -> CGFloat {
        guard let bottleHue = calibration.bottleHue, let bottleSaturation = calibration.bottleSaturation else { return 0 }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }

        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        let region = colorSamplingRegion(faceBox: faceBox)
        let minX = max(0, Int(region.minX * CGFloat(width)))
        let maxX = min(width - 1, Int(region.maxX * CGFloat(width)))
        let minY = max(0, Int((1.0 - region.maxY) * CGFloat(height)))
        let maxY = min(height - 1, Int((1.0 - region.minY) * CGFloat(height)))

        var matchCount = 0
        var sampleCount = 0
        let step = 4

        for y in stride(from: minY, to: maxY, by: step) {
            for x in stride(from: minX, to: maxX, by: step) {
                let offset = y * bytesPerRow + x * 4
                let b = CGFloat(buffer[offset]) / 255.0
                let g = CGFloat(buffer[offset + 1]) / 255.0
                let r = CGFloat(buffer[offset + 2]) / 255.0

                let (h, s, v) = rgbToHSV(r: r, g: g, b: b)
                sampleCount += 1

                guard s > 0.15 && v > 0.15 else { continue }

                let hueDiff = min(abs(h - bottleHue), 360.0 - abs(h - bottleHue))
                if hueDiff < calibration.bottleHueTolerance && abs(s - bottleSaturation) < calibration.bottleSatTolerance {
                    matchCount += 1
                }
            }
        }

        guard sampleCount > 0 else { return 0 }
        return CGFloat(matchCount) / CGFloat(sampleCount)
    }

    private func isBottleColorPresent(pixelBuffer: CVPixelBuffer, faceBox: CGRect, calibration: CalibrationData) -> Bool {
        return bottleColorMatchRatio(pixelBuffer: pixelBuffer, faceBox: faceBox, calibration: calibration) > 0.05
    }

    private func generateColorMatchMask(pixelBuffer: CVPixelBuffer, faceBox: CGRect, calibration: CalibrationData) -> CGImage? {
        guard let bottleHue = calibration.bottleHue, let bottleSaturation = calibration.bottleSaturation else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let srcBuffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        let region = colorSamplingRegion(faceBox: faceBox)
        let roiMinX = max(0, Int(region.minX * CGFloat(width)))
        let roiMaxX = min(width - 1, Int(region.maxX * CGFloat(width)))
        let roiMinY = max(0, Int((1.0 - region.maxY) * CGFloat(height)))
        let roiMaxY = min(height - 1, Int((1.0 - region.minY) * CGFloat(height)))

        let maskBytesPerRow = width * 4
        let maskData = UnsafeMutablePointer<UInt8>.allocate(capacity: height * maskBytesPerRow)
        maskData.initialize(repeating: 0, count: height * maskBytesPerRow)
        defer { maskData.deallocate() }

        let step = 2
        for y in stride(from: roiMinY, to: roiMaxY, by: step) {
            for x in stride(from: roiMinX, to: roiMaxX, by: step) {
                let srcOffset = y * bytesPerRow + x * 4
                let b = CGFloat(srcBuffer[srcOffset]) / 255.0
                let g = CGFloat(srcBuffer[srcOffset + 1]) / 255.0
                let r = CGFloat(srcBuffer[srcOffset + 2]) / 255.0

                let (h, s, v) = rgbToHSV(r: r, g: g, b: b)
                guard s > 0.15 && v > 0.15 else { continue }

                let hueDiff = min(abs(h - bottleHue), 360.0 - abs(h - bottleHue))
                guard hueDiff < calibration.bottleHueTolerance && abs(s - bottleSaturation) < calibration.bottleSatTolerance else { continue }

                for dy in 0..<step {
                    for dx in 0..<step {
                        let py = y + dy
                        let px = x + dx
                        guard py < height, px < width else { continue }
                        let maskOffset = py * maskBytesPerRow + px * 4
                        maskData[maskOffset]     = 255
                        maskData[maskOffset + 1] = 0
                        maskData[maskOffset + 2] = 0
                        maskData[maskOffset + 3] = 120
                    }
                }
            }
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: maskData,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: maskBytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        return context.makeImage()
    }

    private func isAnyHandPointNearFace(handPoints: [CGPoint], faceBox: CGRect) -> Bool {
        let expandedBox = faceBox.insetBy(dx: -faceBox.width * 0.4, dy: -faceBox.height * 0.4)
        return handPoints.contains { expandedBox.contains($0) }
    }

    private func isObjectNearFace(objectCenter: CGPoint, faceCenter: CGPoint, faceBox: CGRect) -> Bool {
        let maxDist = max(faceBox.width, faceBox.height) * 1.5
        let dx = objectCenter.x - faceCenter.x
        let dy = objectCenter.y - faceCenter.y
        return sqrt(dx * dx + dy * dy) <= maxDist
    }
}
