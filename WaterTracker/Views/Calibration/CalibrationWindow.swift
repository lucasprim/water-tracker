import SwiftUI
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - View Model

enum CaptureTarget {
    case baseline, drinking
}

@MainActor
@Observable
final class CalibrationViewModel {
    let webcamMonitor: WebcamMonitor

    var baselineImage: CGImage?
    var baselineOverlay: FrameOverlay?
    var drinkingImage: CGImage?
    var drinkingOverlay: FrameOverlay?

    var countdownValue: Int?
    var captureTarget: CaptureTarget = .baseline

    var selectedHue: Float?
    var selectedSaturation: Float?
    var selectedColor: Color = .clear

    var hueTolerance: Float = 15
    var satTolerance: Float = 0.15

    var selectedAlgorithmID: DetectionAlgorithmID = .colorFingers

    /// True when the displayed image came from disk, not a fresh capture.
    var baselineIsStored = false
    var drinkingIsStored = false

    /// Live testing mode
    var isTesting = false

    var canSave: Bool {
        baselineImage != nil && drinkingImage != nil && selectedHue != nil
    }

    var canTest: Bool {
        baselineImage != nil && drinkingImage != nil && selectedHue != nil
    }

    private var countdownTask: Task<Void, Never>?

    init(webcamMonitor: WebcamMonitor) {
        self.webcamMonitor = webcamMonitor
        // Ensure camera is running — it may have been stopped (goal reached)
        // or errored (previous crash/disconnect)
        if webcamMonitor.status != .running && webcamMonitor.status != .denied {
            webcamMonitor.retry()
        }
        webcamMonitor.enablePreview()
    }

    func loadSaved(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? modelContext.fetch(descriptor).first else { return }

        if let data = settings.baselineImageData, let img = Self.cgImage(from: data) {
            baselineImage = img
            baselineIsStored = true
        }
        if let data = settings.drinkingImageData, let img = Self.cgImage(from: data) {
            drinkingImage = img
            drinkingIsStored = true
        }
        if let hue = settings.bottleColorHue, let sat = settings.bottleColorSaturation {
            selectedHue = hue
            selectedSaturation = sat
            selectedColor = Color(hue: Double(hue) / 360.0, saturation: Double(sat), brightness: 0.9)
        }
        if let ht = settings.bottleColorHueTolerance { hueTolerance = ht }
        if let st = settings.bottleColorSatTolerance { satTolerance = st }
        selectedAlgorithmID = settings.detectionAlgorithm
    }

    func tearDown() {
        countdownTask?.cancel()
        stopTesting()
        webcamMonitor.disablePreview()
    }

    func startTesting() {
        guard canTest else { return }

        // Compute baseline face area from the captured overlay
        let baselineFaceArea: Float
        if let faceBox = baselineOverlay?.faceBox {
            baselineFaceArea = Float(faceBox.width * faceBox.height)
        } else {
            baselineFaceArea = 0.05
        }

        webcamMonitor.updateTestingCalibration(
            baselineArea: baselineFaceArea,
            bottleHue: selectedHue,
            bottleSaturation: selectedSaturation,
            hueTolerance: hueTolerance,
            satTolerance: satTolerance
        )
        webcamMonitor.setDetectionAlgorithm(selectedAlgorithmID)
        webcamMonitor.enableTesting()
        isTesting = true
    }

    func stopTesting() {
        guard isTesting else { return }
        webcamMonitor.disableTesting()
        isTesting = false
    }

    func pushTestingCalibration() {
        guard isTesting else { return }
        let baselineFaceArea: Float
        if let faceBox = baselineOverlay?.faceBox {
            baselineFaceArea = Float(faceBox.width * faceBox.height)
        } else {
            baselineFaceArea = 0.05
        }
        webcamMonitor.updateTestingCalibration(
            baselineArea: baselineFaceArea,
            bottleHue: selectedHue,
            bottleSaturation: selectedSaturation,
            hueTolerance: hueTolerance,
            satTolerance: satTolerance
        )
        webcamMonitor.setDetectionAlgorithm(selectedAlgorithmID)
    }

    func startCountdown(for target: CaptureTarget) {
        captureTarget = target
        countdownTask?.cancel()
        countdownTask = Task {
            for i in (1...3).reversed() {
                countdownValue = i
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            countdownValue = nil
            snapshot(for: target)
        }
    }

    private func snapshot(for target: CaptureTarget) {
        guard let frame = webcamMonitor.latestFrame,
              let overlay = webcamMonitor.latestOverlay else { return }

        switch target {
        case .baseline:
            baselineImage = frame
            baselineOverlay = overlay
            baselineIsStored = false
        case .drinking:
            drinkingImage = frame
            drinkingOverlay = overlay
            drinkingIsStored = false
            // Auto-extract bottle color from overlay
            if let hue = overlay.dominantNonSkinHue, let sat = overlay.dominantNonSkinSaturation {
                selectedHue = hue
                selectedSaturation = sat
                selectedColor = Color(hue: Double(hue) / 360.0, saturation: Double(sat), brightness: 0.9)
            }
        }
    }

    func retakeBaseline() {
        baselineImage = nil
        baselineOverlay = nil
        baselineIsStored = false
    }

    func retakeDrinking() {
        drinkingImage = nil
        drinkingOverlay = nil
        drinkingIsStored = false
        selectedHue = nil
        selectedSaturation = nil
        selectedColor = .clear
    }

    func pickColor(_ color: Color, hue: Float, saturation: Float) {
        selectedColor = color
        selectedHue = hue
        selectedSaturation = saturation
    }

    func save(modelContext: ModelContext) {
        guard canSave else { return }
        stopTesting()

        // Compute calibration values from overlays when available,
        // fall back to stored values if images came from disk.
        let baselineFaceArea: Float
        if let faceBox = baselineOverlay?.faceBox {
            baselineFaceArea = Float(faceBox.width * faceBox.height)
        } else {
            let descriptor = FetchDescriptor<AppSettings>()
            let existing = try? modelContext.fetch(descriptor).first
            baselineFaceArea = existing?.calibratedBaselineQuality ?? 0.05
        }

        let drinkingFaceArea: Float
        if let faceBox = drinkingOverlay?.faceBox {
            drinkingFaceArea = Float(faceBox.width * faceBox.height)
        } else {
            drinkingFaceArea = baselineFaceArea * 0.8
        }

        let dropRatio = 1.0 - (drinkingFaceArea / baselineFaceArea)
        let dropThreshold = max(dropRatio * 0.8, 0.10)

        // Save to AppSettings
        let descriptor = FetchDescriptor<AppSettings>()
        let settings: AppSettings
        if let existing = try? modelContext.fetch(descriptor).first {
            settings = existing
        } else {
            settings = AppSettings()
            modelContext.insert(settings)
        }

        settings.calibratedBaselineQuality = baselineFaceArea
        settings.calibratedDropThreshold = dropThreshold
        settings.bottleColorHue = selectedHue
        settings.bottleColorSaturation = selectedSaturation
        settings.bottleColorHueTolerance = hueTolerance
        settings.bottleColorSatTolerance = satTolerance
        settings.calibrationDate = Date()
        settings.detectionAlgorithm = selectedAlgorithmID

        // Persist photos
        if let img = baselineImage {
            settings.baselineImageData = Self.jpegData(from: img)
        }
        if let img = drinkingImage {
            settings.drinkingImageData = Self.jpegData(from: img)
        }

        try? modelContext.save()

        // Apply immediately to the running monitor
        webcamMonitor.loadCalibration(
            baselineArea: baselineFaceArea,
            dropThreshold: dropThreshold,
            bottleHue: selectedHue,
            bottleSaturation: selectedSaturation,
            hueTolerance: hueTolerance,
            satTolerance: satTolerance
        )
        webcamMonitor.setDetectionAlgorithm(selectedAlgorithmID)
    }

    // MARK: - Image Encoding/Decoding

    private static func jpegData(from image: CGImage, quality: CGFloat = 0.8) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

// MARK: - Calibration Window View

struct CalibrationWindow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CalibrationViewModel

    init(webcamMonitor: WebcamMonitor) {
        _viewModel = State(initialValue: CalibrationViewModel(webcamMonitor: webcamMonitor))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isTesting {
                testingPanel
                    .padding(20)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    baselinePanel
                    drinkingPanel
                }
                .padding(20)
            }

            Divider()

            bottomBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
        }
        .frame(minWidth: 700, minHeight: 580)
        .onAppear {
            viewModel.loadSaved(modelContext: modelContext)
        }
        .onDisappear {
            viewModel.tearDown()
        }
    }

    // MARK: - Baseline Panel (Left)

    private var baselinePanel: some View {
        VStack(spacing: 12) {
            Text("Sit Normally")
                .font(.headline)

            Text("Look at the camera without your bottle")
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack {
                if let captured = viewModel.baselineImage {
                    CameraFrameView(image: captured, showOverlays: false)
                } else {
                    CameraFrameView(image: viewModel.webcamMonitor.latestFrame, showOverlays: false)
                }

                countdownOverlay(for: .baseline)
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(viewModel.baselineImage != nil ? Color.green : Color.secondary.opacity(0.3), lineWidth: 2)
            )

            if viewModel.baselineImage != nil {
                HStack {
                    Label("Captured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Spacer()
                    Button("Retake") {
                        viewModel.retakeBaseline()
                    }
                    .font(.caption)
                }
            } else {
                Button("Capture") {
                    viewModel.startCountdown(for: .baseline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.countdownValue != nil)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Drinking Panel (Right)

    private var drinkingPanel: some View {
        VStack(spacing: 12) {
            Text("Hold Your Bottle")
                .font(.headline)

            Text("Hold your bottle near your face as if drinking")
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack {
                if let captured = viewModel.drinkingImage {
                    CameraFrameView(
                        image: captured,
                        overlay: viewModel.drinkingOverlay,
                        showOverlays: true,
                        onTapColor: { color, hue, sat in
                            viewModel.pickColor(color, hue: hue, saturation: sat)
                        }
                    )
                } else {
                    CameraFrameView(
                        image: viewModel.webcamMonitor.latestFrame,
                        overlay: viewModel.webcamMonitor.latestOverlay,
                        showOverlays: true
                    )
                }

                countdownOverlay(for: .drinking)
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(viewModel.drinkingImage != nil ? Color.green : Color.secondary.opacity(0.3), lineWidth: 2)
            )

            if viewModel.drinkingImage != nil {
                VStack(spacing: 8) {
                    HStack {
                        Label("Captured", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Spacer()
                        Button("Retake") {
                            viewModel.retakeDrinking()
                        }
                        .font(.caption)
                    }

                    colorControls
                }
            } else {
                Button("Capture") {
                    viewModel.startCountdown(for: .drinking)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.countdownValue != nil)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Color Controls

    private var colorControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("Bottle Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                RoundedRectangle(cornerRadius: 4)
                    .fill(viewModel.selectedColor)
                    .frame(width: 24, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.secondary.opacity(0.5), lineWidth: 1)
                    )

                if let hue = viewModel.selectedHue {
                    Text(String(format: "H:%.0f° S:%.0f%%", hue, (viewModel.selectedSaturation ?? 0) * 100))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Tap image to pick")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Text("Hue ±")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
                Slider(value: Binding(
                    get: { viewModel.hueTolerance },
                    set: { viewModel.hueTolerance = $0 }
                ), in: 5...40, step: 1)
                Text(String(format: "%.0f°", viewModel.hueTolerance))
                    .font(.system(.caption2, design: .monospaced))
                    .frame(width: 30, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Text("Sat ±")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
                Slider(value: Binding(
                    get: { viewModel.satTolerance },
                    set: { viewModel.satTolerance = $0 }
                ), in: 0.05...0.40, step: 0.01)
                Text(String(format: "%.0f%%", viewModel.satTolerance * 100))
                    .font(.system(.caption2, design: .monospaced))
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }

    // MARK: - Testing Panel

    private var testingPanel: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left: Live camera feed with overlays
            VStack(spacing: 8) {
                Text("Live Detection Test")
                    .font(.headline)

                let signals = viewModel.webcamMonitor.latestDetectionSignals
                ZStack {
                    CameraFrameView(
                        image: viewModel.webcamMonitor.latestFrame,
                        overlay: viewModel.webcamMonitor.latestOverlay,
                        showOverlays: true
                    )

                    if let mask = viewModel.webcamMonitor.latestColorMatchMask {
                        GeometryReader { geo in
                            let nsImage = NSImage(cgImage: mask, size: NSSize(width: mask.width, height: mask.height))
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(minHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(signals?.isDrinking == true ? Color.green : Color.secondary.opacity(0.3), lineWidth: signals?.isDrinking == true ? 3 : 2)
                )
            }
            .frame(maxWidth: .infinity)

            // Right: Signal indicators + tolerance sliders
            VStack(alignment: .leading, spacing: 12) {
                Text("Signals")
                    .font(.headline)

                signalIndicators

                Divider()

                testingColorControls
            }
            .frame(width: 220)
        }
    }

    private var signalIndicators: some View {
        let signals = viewModel.webcamMonitor.latestDetectionSignals

        return VStack(alignment: .leading, spacing: 8) {
            signalRow(
                label: "Face",
                active: signals?.faceDetected == true,
                detail: signals.map { String(format: "%.1f%%", $0.faceArea * 100) }
            )
            signalRow(
                label: "Fingers",
                active: signals?.handNearFace == true,
                detail: nil
            )
            signalRow(
                label: "Color",
                active: signals.map { $0.colorMatchRatio > $0.colorMatchThreshold } ?? false,
                detail: signals.map { String(format: "%.0f%%", $0.colorMatchRatio * 100) }
            )
            signalRow(
                label: "Object",
                active: signals?.objectNearFace == true,
                detail: signals?.objectLabel
            )

            Divider()

            if signals?.isDrinking == true {
                HStack {
                    Image(systemName: "drop.fill")
                        .foregroundStyle(.blue)
                    Text("DRINKING")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(.blue)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                if let reason = signals?.triggerReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "drop")
                        .foregroundStyle(.secondary)
                    Text("Not drinking")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func signalRow(label: String, active: Bool, detail: String?) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(active ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 50, alignment: .leading)
            if let detail {
                Text(detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: active ? "checkmark" : "xmark")
                .font(.caption2)
                .foregroundStyle(active ? .green : .secondary)
        }
    }

    private var testingColorControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("Bottle Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                RoundedRectangle(cornerRadius: 4)
                    .fill(viewModel.selectedColor)
                    .frame(width: 24, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.secondary.opacity(0.5), lineWidth: 1)
                    )

                Spacer()
            }

            HStack(spacing: 8) {
                Text("Hue ±")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
                Slider(value: Binding(
                    get: { viewModel.hueTolerance },
                    set: {
                        viewModel.hueTolerance = $0
                        viewModel.pushTestingCalibration()
                    }
                ), in: 5...40, step: 1)
                Text(String(format: "%.0f°", viewModel.hueTolerance))
                    .font(.system(.caption2, design: .monospaced))
                    .frame(width: 30, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Text("Sat ±")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
                Slider(value: Binding(
                    get: { viewModel.satTolerance },
                    set: {
                        viewModel.satTolerance = $0
                        viewModel.pushTestingCalibration()
                    }
                ), in: 0.05...0.40, step: 0.01)
                Text(String(format: "%.0f%%", viewModel.satTolerance * 100))
                    .font(.system(.caption2, design: .monospaced))
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }

    // MARK: - Countdown Overlay

    @ViewBuilder
    private func countdownOverlay(for target: CaptureTarget) -> some View {
        if viewModel.captureTarget == target, let count = viewModel.countdownValue {
            ZStack {
                Color.black.opacity(0.4)
                Text("\(count)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: count)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text("Algorithm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Algorithm", selection: Binding(
                    get: { viewModel.selectedAlgorithmID },
                    set: {
                        viewModel.selectedAlgorithmID = $0
                        viewModel.pushTestingCalibration()
                    }
                )) {
                    ForEach(DetectionAlgorithmID.allCases, id: \.self) { algo in
                        Text(algo.displayName).tag(algo)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Text(viewModel.selectedAlgorithmID.description)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)

                Spacer()
            }

            HStack {
                Button("Cancel") {
                    viewModel.tearDown()
                    dismiss()
                }

                if viewModel.isTesting {
                    Button("Back") {
                        viewModel.stopTesting()
                    }
                }

                Spacer()

                if !viewModel.isTesting && viewModel.canSave {
                    Label("Ready to save", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Spacer()

                if viewModel.canTest && !viewModel.isTesting {
                    Button("Test Calibration") {
                        viewModel.startTesting()
                    }
                }

                Button("Save Calibration") {
                    viewModel.save(modelContext: modelContext)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSave)
            }
        }
    }
}
