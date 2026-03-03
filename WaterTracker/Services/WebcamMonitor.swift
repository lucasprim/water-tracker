@preconcurrency import AVFoundation
import Vision
import CoreML
import CoreImage
import Observation
import os

private let logger = Logger(subsystem: "com.lucasprim.water-tracker", category: "WebcamMonitor")

struct FrameOverlay: Sendable {
    let faceBox: CGRect?                           // normalized 0-1
    let handPoints: [CGPoint]                      // normalized 0-1
    let objectDetections: [(label: String, confidence: Float, box: CGRect)]
    let dominantNonSkinHue: Float?
    let dominantNonSkinSaturation: Float?
}

struct DetectionSignals: Sendable {
    let faceDetected: Bool
    let faceArea: Float
    let baseline: Float
    let handNearFace: Bool
    let colorMatchRatio: Float      // 0.0–1.0 continuous value
    let colorMatchThreshold: Float  // 0.05
    let objectNearFace: Bool
    let objectLabel: String?
    let objectConfidence: Float
    let isDrinking: Bool
    let triggerReason: String?
    let colorMatchMask: CGImage?    // semi-transparent red overlay of matched pixels
}

@MainActor
@Observable
final class WebcamMonitor {
    enum CameraStatus: String {
        case notDetermined, authorized, denied, running, stopped, error, interrupted
    }

    enum CalibrationPhase {
        case idle
        case baseline   // "Sit normally" — collecting face area
        case drinking   // "Take a drink" — measuring face area + bottle color
    }

    private(set) var status: CameraStatus = .notDetermined
    private(set) var errorMessage: String?
    private(set) var detectionLog: [String] = []
    private(set) var calibrationPhase: CalibrationPhase = .idle

    var onDrinkingDetected: (() -> Void)?
    /// (baselineArea, dropThreshold, bottleHue?, bottleSaturation?)
    var onCalibrationComplete: ((Float, Float, Float?, Float?) -> Void)?

    /// True while positive detection frames are arriving (for menu bar icon)
    private(set) var isDrinkingActive = false
    private var drinkingDeactivationTask: Task<Void, Never>?

    // Preview mode for calibration UI
    private(set) var latestFrame: CGImage?
    private(set) var latestOverlay: FrameOverlay?
    private var previewEnabled = false

    // Testing mode for live calibration verification
    private(set) var latestDetectionSignals: DetectionSignals?
    private(set) var latestColorMatchMask: CGImage?

    private let sessionQueue = DispatchQueue(label: "com.lucasprim.water-tracker.webcam-session")
    private let captureDelegate = CaptureDelegate()
    private var session: AVCaptureSession?
    private var sessionObservers: [NSObjectProtocol] = []
    /// Sliding window of recent frame results (true = drinking detected).
    private var recentFrameResults: [Bool] = []
    private let windowSize = 8
    private let requiredPositiveFrames = 2
    private let maxLogEntries = 60

    func start() {
        logger.notice("WebcamMonitor.start() called, current status: \(self.status.rawValue)")
        checkPermissionAndStart()
    }

    func stop() {
        logger.notice("WebcamMonitor.stop() called")
        removeSessionObservers()
        let sessionToStop = session
        session = nil
        status = .stopped
        errorMessage = nil
        recentFrameResults.removeAll()
        sessionQueue.async { sessionToStop?.stopRunning() }
    }

    func retry() {
        logger.notice("WebcamMonitor.retry() called, current status: \(self.status.rawValue)")
        stop()
        checkPermissionAndStart()
    }

    func enablePreview() {
        previewEnabled = true
        captureDelegate.previewEnabled = true
    }

    func disablePreview() {
        previewEnabled = false
        captureDelegate.previewEnabled = false
        latestFrame = nil
        latestOverlay = nil
    }

    func enableTesting() {
        captureDelegate.testingEnabled = true
        enablePreview()
    }

    func disableTesting() {
        captureDelegate.testingEnabled = false
        latestDetectionSignals = nil
        latestColorMatchMask = nil
    }

    func updateTestingCalibration(baselineArea: Float, bottleHue: Float?, bottleSaturation: Float?, hueTolerance: Float, satTolerance: Float) {
        captureDelegate.calibratedBaseline = CGFloat(baselineArea)
        if let hue = bottleHue, let sat = bottleSaturation {
            captureDelegate.bottleHue = CGFloat(hue)
            captureDelegate.bottleSaturation = CGFloat(sat)
        }
        captureDelegate.bottleHueTolerance = CGFloat(hueTolerance)
        captureDelegate.bottleSatTolerance = CGFloat(satTolerance)
    }

    func loadCalibration(baselineArea: Float, dropThreshold: Float, bottleHue: Float?, bottleSaturation: Float?, hueTolerance: Float? = nil, satTolerance: Float? = nil) {
        // Sanity check: face bounding box area in normalized coords is typically 0.02–0.25.
        // Values outside this range are stale data from the old face-quality system.
        if baselineArea > 0.01 && baselineArea < 0.30 {
            captureDelegate.calibratedBaseline = CGFloat(baselineArea)
            captureDelegate.calibratedDropThreshold = CGFloat(dropThreshold)
            logger.notice("Loaded calibration: baseline=\(baselineArea), drop=\(dropThreshold)")
        } else {
            logger.warning("Ignoring stale calibration: baseline=\(baselineArea) out of face-area range")
        }
        if let hue = bottleHue, let sat = bottleSaturation {
            captureDelegate.bottleHue = CGFloat(hue)
            captureDelegate.bottleSaturation = CGFloat(sat)
            logger.notice("Loaded bottle color: hue=\(hue), sat=\(sat)")
        }
        if let ht = hueTolerance {
            captureDelegate.bottleHueTolerance = CGFloat(ht)
        }
        if let st = satTolerance {
            captureDelegate.bottleSatTolerance = CGFloat(st)
        }
    }

    func startCalibration() {
        calibrationPhase = .baseline
        captureDelegate.startCalibrationPhase(.baseline)

        Task {
            try? await Task.sleep(for: .seconds(3))
            guard calibrationPhase == .baseline else { return }

            let baselineSamples = captureDelegate.calibrationSamples
            guard !baselineSamples.isEmpty else {
                calibrationPhase = .idle
                captureDelegate.startCalibrationPhase(.idle)
                return
            }
            let baselineMedian = baselineSamples.sorted()[baselineSamples.count / 2]

            calibrationPhase = .drinking
            captureDelegate.startCalibrationPhase(.drinking)

            try? await Task.sleep(for: .seconds(5))
            guard calibrationPhase == .drinking else { return }

            let drinkSamples = captureDelegate.calibrationSamples
            let colorSamples = captureDelegate.calibrationColorSamples
            calibrationPhase = .idle
            captureDelegate.startCalibrationPhase(.idle)

            guard !drinkSamples.isEmpty else { return }

            // Compute face area drop threshold
            let minArea = drinkSamples.min()!
            let dropRatio = 1.0 - (minArea / baselineMedian)
            let threshold = max(dropRatio * 0.8, 0.10)

            captureDelegate.calibratedBaseline = baselineMedian
            captureDelegate.calibratedDropThreshold = threshold

            // Compute bottle color from collected HSV samples
            var hue: Float?
            var sat: Float?
            if !colorSamples.isEmpty {
                let sortedHues = colorSamples.map(\.hue).sorted()
                let sortedSats = colorSamples.map(\.saturation).sorted()
                let medianHue = sortedHues[sortedHues.count / 2]
                let medianSat = sortedSats[sortedSats.count / 2]
                captureDelegate.bottleHue = medianHue
                captureDelegate.bottleSaturation = medianSat
                hue = Float(medianHue)
                sat = Float(medianSat)
                logger.notice("Calibrated bottle color: hue=\(hue!), sat=\(sat!)")
            }

            onCalibrationComplete?(Float(baselineMedian), Float(threshold), hue, sat)
        }
    }

    // MARK: - Permission

    private func checkPermissionAndStart() {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        logger.notice("Camera authorization status: \(authStatus.rawValue)")

        switch authStatus {
        case .authorized:
            status = .authorized
            setupAndStartSession()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    status = .authorized
                    setupAndStartSession()
                } else {
                    status = .denied
                }
            }
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .denied
        }
    }

    // MARK: - Capture Session

    private func setupAndStartSession() {
        captureDelegate.onFrameAnalyzed = { [weak self] isDrinking, logEntry in
            Task { @MainActor in
                self?.handleFrameResult(isDrinking: isDrinking, logEntry: logEntry)
            }
        }

        captureDelegate.onPreviewFrame = { [weak self] cgImage, overlay in
            Task { @MainActor in
                guard let self, self.previewEnabled else { return }
                self.latestFrame = cgImage
                self.latestOverlay = overlay
            }
        }

        captureDelegate.onTestingSignals = { [weak self] signals in
            Task { @MainActor in
                guard let self else { return }
                self.latestDetectionSignals = signals
                self.latestColorMatchMask = signals.colorMatchMask
            }
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.loadObjectDetectionModel()
            self.configureSessionOnBackground()
        }
    }

    private nonisolated func loadObjectDetectionModel() {
        do {
            guard let modelURL = Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc") else {
                logger.warning("YOLOv8n model not found in bundle. Object detection disabled.")
                return
            }
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
            let vnModel = try VNCoreMLModel(for: mlModel)
            captureDelegate.configureObjectDetection(vnModel: vnModel)
            logger.notice("YOLOv8n model loaded successfully")
        } catch {
            logger.error("Failed to load YOLOv8n: \(error.localizedDescription). Object detection disabled.")
        }
    }

    private nonisolated func configureSessionOnBackground() {
        logger.notice("Configuring capture session...")

        let session = AVCaptureSession()
        session.beginConfiguration()

        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }

        guard let camera = AVCaptureDevice.default(for: .video) else {
            logger.error("No video capture device found")
            Task { @MainActor in self.setError("No camera found") }
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                logger.error("Cannot add camera input")
                Task { @MainActor in self.setError("Cannot connect to camera") }
                session.commitConfiguration()
                return
            }
        } catch {
            logger.error("Failed to create camera input: \(error.localizedDescription)")
            Task { @MainActor in self.setError("Camera unavailable: \(error.localizedDescription)") }
            session.commitConfiguration()
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        // Force BGRA pixel format for reliable color sampling
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(
            captureDelegate,
            queue: DispatchQueue(label: "com.lucasprim.water-tracker.webcam-frames", qos: .userInitiated)
        )

        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            logger.error("Cannot add video output")
            Task { @MainActor in self.setError("Cannot configure camera output") }
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()

        // Use the lowest supported frame rate to save resources
        do {
            try camera.lockForConfiguration()
            if let minRate = camera.activeFormat.videoSupportedFrameRateRanges.map(\.minFrameRate).min(),
               minRate > 0 {
                let duration = CMTime(value: 1, timescale: CMTimeScale(minRate))
                camera.activeVideoMinFrameDuration = duration
                camera.activeVideoMaxFrameDuration = duration
                logger.info("Set frame rate to \(minRate) fps (lowest supported)")
            }
            camera.unlockForConfiguration()
        } catch {
            logger.warning("Could not set frame rate: \(error.localizedDescription)")
        }

        session.startRunning()
        let isRunning = session.isRunning
        logger.notice("Session started, isRunning: \(isRunning), preset: \(session.sessionPreset.rawValue)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            if isRunning {
                self.session = session
                self.status = .running
                self.errorMessage = nil
                self.observeSession(session)
            } else {
                self.setError("Camera session failed to start")
            }
        }
    }

    // MARK: - Session Observation

    private func observeSession(_ session: AVCaptureSession) {
        removeSessionObservers()

        let interruptedObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let message = "Camera interrupted"
                logger.warning("Session interrupted")
                self.status = .interrupted
                self.errorMessage = message
            }
        }

        let resumedObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                logger.notice("Session interruption ended — resuming")
                self.status = .running
                self.errorMessage = nil
            }
        }

        let runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
                let message = error?.localizedDescription ?? "Camera error"
                logger.error("Session runtime error: \(message)")
                self.setError(message)
            }
        }

        sessionObservers = [interruptedObserver, resumedObserver, runtimeErrorObserver]
    }

    private func removeSessionObservers() {
        for observer in sessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionObservers.removeAll()
    }

    private func setError(_ message: String) {
        status = .error
        errorMessage = message
    }

    // MARK: - Detection Logic

    private func handleFrameResult(isDrinking: Bool, logEntry: String) {
        detectionLog.append(logEntry)
        if detectionLog.count > maxLogEntries {
            detectionLog.removeFirst(detectionLog.count - maxLogEntries)
        }

        // Update drinking-active indicator for menu bar icon
        if isDrinking {
            isDrinkingActive = true
            drinkingDeactivationTask?.cancel()
            drinkingDeactivationTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                isDrinkingActive = false
            }
        }

        recentFrameResults.append(isDrinking)
        if recentFrameResults.count > windowSize {
            recentFrameResults.removeFirst()
        }

        let positiveCount = recentFrameResults.filter { $0 }.count
        if positiveCount >= requiredPositiveFrames {
            logger.notice("Drinking detected! (\(positiveCount)/\(self.windowSize) positive frames)")
            detectionLog.append(">>> TRIGGERED (\(positiveCount)/\(self.windowSize) positive)")
            recentFrameResults.removeAll()
            onDrinkingDetected?()
        }
    }
}

// MARK: - Capture Delegate

private final class CaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Callback: (isDrinking, logEntry)
    var onFrameAnalyzed: (@Sendable (Bool, String) -> Void)?
    /// Callback for preview frames: (CGImage, FrameOverlay)
    var onPreviewFrame: (@Sendable (CGImage, FrameOverlay) -> Void)?
    /// Callback for testing signals
    var onTestingSignals: (@Sendable (DetectionSignals) -> Void)?
    /// Whether preview mode is active
    var previewEnabled = false
    /// Whether testing mode is active
    var testingEnabled = false

    // Vision requests
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let handRequest: VNDetectHumanHandPoseRequest = {
        let req = VNDetectHumanHandPoseRequest()
        req.maximumHandCount = 2
        return req
    }()
    private var objectRequest: VNCoreMLRequest?

    // CIContext for pixel buffer → CGImage conversion
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Adaptive face area baseline (rolling window, 80th percentile)
    private var faceAreaHistory: [CGFloat] = []
    private let baselineWindowSize = 30
    private var adaptiveBaseline: CGFloat = 0

    // Calibration overrides
    var calibratedBaseline: CGFloat?
    var calibratedDropThreshold: CGFloat?

    // Bottle color (HSV)
    var bottleHue: CGFloat?         // 0–360
    var bottleSaturation: CGFloat?  // 0–1
    var bottleHueTolerance: CGFloat = 30    // degrees
    var bottleSatTolerance: CGFloat = 0.30  // 0–1

    // Calibration collection
    private(set) var calibrationSamples: [CGFloat] = []
    private(set) var calibrationColorSamples: [(hue: CGFloat, saturation: CGFloat)] = []
    private var currentCalibrationPhase: WebcamMonitor.CalibrationPhase = .idle

    // Frame management
    private var frameCount = 0
    private var lastAnalysisTime: CFAbsoluteTime = 0
    private let analysisInterval: CFAbsoluteTime = 0.5

    private let drinkObjectClasses: Set<String> = ["bottle", "cup"]

    func configureObjectDetection(vnModel: VNCoreMLModel) {
        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill
        objectRequest = request
    }

    func startCalibrationPhase(_ phase: WebcamMonitor.CalibrationPhase) {
        calibrationSamples.removeAll()
        calibrationColorSamples.removeAll()
        currentCalibrationPhase = phase
    }

    // MARK: - Frame Processing

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCount += 1
        if frameCount == 1 {
            logger.notice("First frame received from camera")
        }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAnalysisTime >= analysisInterval else { return }
        lastAnalysisTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        var requests: [VNRequest] = [faceRequest, handRequest]
        if let objectRequest { requests.append(objectRequest) }

        do {
            try handler.perform(requests)
        } catch {
            return
        }

        // Publish preview frame if enabled
        if previewEnabled {
            publishPreviewFrame(pixelBuffer: pixelBuffer)
        }

        // Testing mode: compute signals, publish, skip normal detection
        if testingEnabled {
            let signals = computeTestingSignals(pixelBuffer: pixelBuffer)
            onTestingSignals?(signals)
            return
        }

        // Calibration mode
        if currentCalibrationPhase != .idle {
            handleCalibrationFrame(pixelBuffer: pixelBuffer)
            return
        }

        let (isDrinking, logEntry) = fuseSignals(pixelBuffer: pixelBuffer)
        onFrameAnalyzed?(isDrinking, logEntry)
    }

    private func publishPreviewFrame(pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let face = faceRequest.results?.first
        let faceBox = face?.boundingBox

        let hands = handRequest.results ?? []
        let handJointKeys: [VNHumanHandPoseObservation.JointName] = [
            .wrist, .indexTip, .middleTip, .ringTip, .littleTip, .thumbTip,
            .indexMCP, .middleMCP, .ringMCP, .littleMCP,
        ]
        let handPoints: [CGPoint] = hands.flatMap { hand in
            handJointKeys.compactMap { key in
                guard let point = try? hand.recognizedPoint(key),
                      point.confidence >= 0.25 else { return nil }
                return point.location
            }
        }

        let objectDetections: [(label: String, confidence: Float, box: CGRect)] = {
            guard let results = objectRequest?.results as? [VNRecognizedObjectObservation] else { return [] }
            return results.compactMap { obs in
                guard let topLabel = obs.labels.first,
                      drinkObjectClasses.contains(topLabel.identifier),
                      topLabel.confidence >= 0.3 else { return nil }
                return (topLabel.identifier, topLabel.confidence, obs.boundingBox)
            }
        }()

        var nonSkinHue: Float?
        var nonSkinSat: Float?
        if let faceBox {
            if let color = extractDominantNonSkinColor(pixelBuffer: pixelBuffer, faceBox: faceBox) {
                nonSkinHue = Float(color.hue)
                nonSkinSat = Float(color.saturation)
            }
        }

        let overlay = FrameOverlay(
            faceBox: faceBox,
            handPoints: handPoints,
            objectDetections: objectDetections,
            dominantNonSkinHue: nonSkinHue,
            dominantNonSkinSaturation: nonSkinSat
        )

        onPreviewFrame?(cgImage, overlay)
    }

    // MARK: - Calibration

    private func handleCalibrationFrame(pixelBuffer: CVPixelBuffer) {
        guard let face = faceRequest.results?.first else { return }
        let area = face.boundingBox.width * face.boundingBox.height
        calibrationSamples.append(area)

        // During drinking phase, sample the dominant non-skin color in the face region
        if currentCalibrationPhase == .drinking {
            if let color = extractDominantNonSkinColor(pixelBuffer: pixelBuffer, faceBox: face.boundingBox) {
                calibrationColorSamples.append(color)
            }
        }
    }

    // MARK: - Multi-Signal Fusion

    private func fuseSignals(pixelBuffer: CVPixelBuffer) -> (Bool, String) {
        let face = faceRequest.results?.first
        let faceBox = face?.boundingBox

        // Extract hand joint positions (wrist + fingertips for better coverage)
        let hands = handRequest.results ?? []
        let handJointKeys: [VNHumanHandPoseObservation.JointName] = [
            .wrist, .indexTip, .middleTip, .ringTip, .littleTip, .thumbTip,
            .indexMCP, .middleMCP, .ringMCP, .littleMCP,
        ]
        let handPoints: [CGPoint] = hands.flatMap { hand in
            handJointKeys.compactMap { key in
                guard let point = try? hand.recognizedPoint(key),
                      point.confidence >= 0.25 else { return nil }
                return point.location
            }
        }

        // Extract drink-related object detections (bottle/cup with conf >= 0.4)
        let drinkObjects: [(center: CGPoint, confidence: Float, label: String)] = {
            guard let results = objectRequest?.results as? [VNRecognizedObjectObservation] else { return [] }
            return results.compactMap { obs in
                guard let topLabel = obs.labels.first,
                      drinkObjectClasses.contains(topLabel.identifier),
                      topLabel.confidence >= 0.4 else { return nil }
                let box = obs.boundingBox
                return (CGPoint(x: box.midX, y: box.midY), topLabel.confidence, topLabel.identifier)
            }
        }()

        guard let faceBox else {
            return (false, "no face")
        }

        let faceArea = faceBox.width * faceBox.height
        let faceCenter = CGPoint(x: faceBox.midX, y: faceBox.midY)
        let handNearFace = isAnyHandPointNearFace(handPoints: handPoints, faceBox: faceBox)

        // Update adaptive baseline only when no hand near face (avoids poisoning during drinking)
        if !handNearFace {
            updateBaseline(area: faceArea)
        }

        let baseline = currentBaseline
        let hasBottleColor = bottleHue != nil
        let colorTag = hasBottleColor ? "C" : "-"
        let log = String(format: "F=(%.2f,%.2f,%.2f,%.2f) H=%d O=%d %@ base=%.3f",
                         faceBox.minX, faceBox.minY, faceBox.width, faceBox.height,
                         handPoints.count, drinkObjects.count, colorTag, baseline)

        // Strong trigger: drink object detected near face and above midframe
        for obj in drinkObjects {
            if obj.center.y > 0.35
                && isObjectNearFace(objectCenter: obj.center, faceCenter: faceCenter, faceBox: faceBox) {
                let triggerLog = String(format: "DRINK(bottle@face) obj=(%.2f,%.2f) conf=%.2f",
                                        obj.center.x, obj.center.y, obj.confidence)
                return (true, triggerLog)
            }
        }

        // Moderate trigger: hand near face + confirmation signal
        if handNearFace {
            if hasBottleColor {
                // Calibrated: bottle color must be present (no fallback — color IS the gate)
                let colorPresent = isBottleColorPresent(pixelBuffer: pixelBuffer, faceBox: faceBox)
                if colorPresent {
                    let handPos = handPoints.first ?? .zero
                    let triggerLog = String(format: "DRINK(hand+color) H@(%.2f,%.2f)",
                                            handPos.x, handPos.y)
                    return (true, triggerLog)
                }
            } else if baseline > 0 {
                // Uncalibrated fallback: require significant face area drop
                let dropRatio = 1.0 - (faceArea / baseline)
                if dropRatio > 0.30 {
                    let handPos = handPoints.first ?? .zero
                    let triggerLog = String(format: "DRINK(hand+occ) area=%.3f drop=%.0f%% H@(%.2f,%.2f)",
                                            faceArea, dropRatio * 100, handPos.x, handPos.y)
                    return (true, triggerLog)
                }
            }
        }

        if frameCount % 10 == 0 {
            logger.notice("\(log, privacy: .public) (frame \(self.frameCount))")
        }

        return (false, log)
    }

    private var currentBaseline: CGFloat {
        calibratedBaseline ?? adaptiveBaseline
    }

    // MARK: - Testing Mode

    private func computeTestingSignals(pixelBuffer: CVPixelBuffer) -> DetectionSignals {
        let face = faceRequest.results?.first
        let faceBox = face?.boundingBox

        let hands = handRequest.results ?? []
        let handJointKeys: [VNHumanHandPoseObservation.JointName] = [
            .wrist, .indexTip, .middleTip, .ringTip, .littleTip, .thumbTip,
            .indexMCP, .middleMCP, .ringMCP, .littleMCP,
        ]
        let handPoints: [CGPoint] = hands.flatMap { hand in
            handJointKeys.compactMap { key in
                guard let point = try? hand.recognizedPoint(key),
                      point.confidence >= 0.25 else { return nil }
                return point.location
            }
        }

        let drinkObjects: [(center: CGPoint, confidence: Float, label: String)] = {
            guard let results = objectRequest?.results as? [VNRecognizedObjectObservation] else { return [] }
            return results.compactMap { obs in
                guard let topLabel = obs.labels.first,
                      drinkObjectClasses.contains(topLabel.identifier),
                      topLabel.confidence >= 0.3 else { return nil }
                let box = obs.boundingBox
                return (CGPoint(x: box.midX, y: box.midY), topLabel.confidence, topLabel.identifier)
            }
        }()

        guard let faceBox else {
            return DetectionSignals(
                faceDetected: false, faceArea: 0, baseline: Float(currentBaseline),
                handNearFace: false, colorMatchRatio: 0, colorMatchThreshold: 0.05,
                objectNearFace: false, objectLabel: nil, objectConfidence: 0,
                isDrinking: false, triggerReason: nil, colorMatchMask: nil
            )
        }

        let faceArea = Float(faceBox.width * faceBox.height)
        let faceCenter = CGPoint(x: faceBox.midX, y: faceBox.midY)
        let handNearFace = isAnyHandPointNearFace(handPoints: handPoints, faceBox: faceBox)
        let colorRatio = Float(bottleColorMatchRatio(pixelBuffer: pixelBuffer, faceBox: faceBox))
        let mask = generateColorMatchMask(pixelBuffer: pixelBuffer, faceBox: faceBox)

        // Find best drink object near face
        var objectNearFace = false
        var objectLabel: String?
        var objectConfidence: Float = 0
        for obj in drinkObjects {
            if obj.center.y > 0.35
                && isObjectNearFace(objectCenter: obj.center, faceCenter: faceCenter, faceBox: faceBox) {
                objectNearFace = true
                objectLabel = obj.label
                objectConfidence = obj.confidence
                break
            }
        }

        // Determine if drinking (same logic as fuseSignals, read-only)
        var isDrinking = false
        var triggerReason: String?

        if objectNearFace {
            isDrinking = true
            triggerReason = "Object near face (\(objectLabel ?? "?"))"
        } else if handNearFace {
            if bottleHue != nil && colorRatio > 0.05 {
                isDrinking = true
                triggerReason = "Hand + color match (\(Int(colorRatio * 100))%)"
            } else if bottleHue == nil, currentBaseline > 0 {
                let dropRatio = 1.0 - (CGFloat(faceArea) / currentBaseline)
                if dropRatio > 0.30 {
                    isDrinking = true
                    triggerReason = "Hand + face occlusion (\(Int(dropRatio * 100))%)"
                }
            }
        }

        return DetectionSignals(
            faceDetected: true, faceArea: faceArea, baseline: Float(currentBaseline),
            handNearFace: handNearFace, colorMatchRatio: colorRatio, colorMatchThreshold: 0.05,
            objectNearFace: objectNearFace, objectLabel: objectLabel, objectConfidence: objectConfidence,
            isDrinking: isDrinking, triggerReason: triggerReason, colorMatchMask: mask
        )
    }

    // MARK: - Color Analysis

    /// Returns the ratio (0.0–1.0) of pixels matching the calibrated bottle color in the face region.
    private func bottleColorMatchRatio(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> CGFloat {
        guard let bottleHue, let bottleSaturation else { return 0 }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }

        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Expanded face region (where bottle would appear)
        let expandedBox = faceBox.insetBy(dx: -faceBox.width * 0.5, dy: -faceBox.height * 0.5)

        // Vision coords (bottom-left origin) → pixel coords (top-left origin)
        let minX = max(0, Int(expandedBox.minX * CGFloat(width)))
        let maxX = min(width - 1, Int(expandedBox.maxX * CGFloat(width)))
        let minY = max(0, Int((1.0 - expandedBox.maxY) * CGFloat(height)))
        let maxY = min(height - 1, Int((1.0 - expandedBox.minY) * CGFloat(height)))

        var matchCount = 0
        var sampleCount = 0
        let step = 4 // subsample for speed

        for y in stride(from: minY, to: maxY, by: step) {
            for x in stride(from: minX, to: maxX, by: step) {
                let offset = y * bytesPerRow + x * 4 // BGRA
                let b = CGFloat(buffer[offset]) / 255.0
                let g = CGFloat(buffer[offset + 1]) / 255.0
                let r = CGFloat(buffer[offset + 2]) / 255.0

                let (h, s, v) = rgbToHSV(r: r, g: g, b: b)
                sampleCount += 1

                // Skip very dark or unsaturated pixels
                guard s > 0.15 && v > 0.15 else { continue }

                let hueDiff = min(abs(h - bottleHue), 360.0 - abs(h - bottleHue))
                if hueDiff < bottleHueTolerance && abs(s - bottleSaturation) < bottleSatTolerance {
                    matchCount += 1
                }
            }
        }

        guard sampleCount > 0 else { return 0 }
        return CGFloat(matchCount) / CGFloat(sampleCount)
    }

    /// Check if the calibrated bottle color is present in the face region of the frame.
    private func isBottleColorPresent(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> Bool {
        return bottleColorMatchRatio(pixelBuffer: pixelBuffer, faceBox: faceBox) > 0.05
    }

    /// Generate a semi-transparent red mask image highlighting pixels that match the bottle color.
    private func generateColorMatchMask(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> CGImage? {
        guard let bottleHue, let bottleSaturation else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let srcBuffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Expanded face region
        let expandedBox = faceBox.insetBy(dx: -faceBox.width * 0.5, dy: -faceBox.height * 0.5)
        let roiMinX = max(0, Int(expandedBox.minX * CGFloat(width)))
        let roiMaxX = min(width - 1, Int(expandedBox.maxX * CGFloat(width)))
        let roiMinY = max(0, Int((1.0 - expandedBox.maxY) * CGFloat(height)))
        let roiMaxY = min(height - 1, Int((1.0 - expandedBox.minY) * CGFloat(height)))

        // Create RGBA mask buffer (full frame size, all transparent)
        let maskBytesPerRow = width * 4
        let maskData = UnsafeMutablePointer<UInt8>.allocate(capacity: height * maskBytesPerRow)
        maskData.initialize(repeating: 0, count: height * maskBytesPerRow)
        defer { maskData.deallocate() }

        // Paint matching pixels red (step=2 for decent resolution without being too slow)
        let step = 2
        for y in stride(from: roiMinY, to: roiMaxY, by: step) {
            for x in stride(from: roiMinX, to: roiMaxX, by: step) {
                let srcOffset = y * bytesPerRow + x * 4 // BGRA
                let b = CGFloat(srcBuffer[srcOffset]) / 255.0
                let g = CGFloat(srcBuffer[srcOffset + 1]) / 255.0
                let r = CGFloat(srcBuffer[srcOffset + 2]) / 255.0

                let (h, s, v) = rgbToHSV(r: r, g: g, b: b)
                guard s > 0.15 && v > 0.15 else { continue }

                let hueDiff = min(abs(h - bottleHue), 360.0 - abs(h - bottleHue))
                guard hueDiff < bottleHueTolerance && abs(s - bottleSaturation) < bottleSatTolerance else { continue }

                // Fill a step×step block with semi-transparent red
                for dy in 0..<step {
                    for dx in 0..<step {
                        let py = y + dy
                        let px = x + dx
                        guard py < height, px < width else { continue }
                        let maskOffset = py * maskBytesPerRow + px * 4
                        maskData[maskOffset]     = 255  // R
                        maskData[maskOffset + 1] = 0    // G
                        maskData[maskOffset + 2] = 0    // B
                        maskData[maskOffset + 3] = 120  // A (~47% opacity)
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

    /// Extract the dominant non-skin color from the face region (for calibration).
    private func extractDominantNonSkinColor(
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

                // Filter: must be saturated and not too dark, and NOT skin-toned
                // Skin hues are roughly 0–50° (red/orange/yellow)
                guard s > 0.20 && v > 0.20 else { continue }
                guard h > 55 && h < 340 else { continue } // skip skin-range hues and reds

                nonSkinHues.append((hue: h, saturation: s))
            }
        }

        guard nonSkinHues.count >= 5 else { return nil }

        // Return median hue and saturation
        let sortedH = nonSkinHues.map(\.hue).sorted()
        let sortedS = nonSkinHues.map(\.saturation).sorted()
        return (hue: sortedH[sortedH.count / 2], saturation: sortedS[sortedS.count / 2])
    }

    // MARK: - Helpers

    /// Check if object center is within 1.5x face dimensions from face center.
    private func isObjectNearFace(objectCenter: CGPoint, faceCenter: CGPoint, faceBox: CGRect) -> Bool {
        let maxDist = max(faceBox.width, faceBox.height) * 1.5
        let dx = objectCenter.x - faceCenter.x
        let dy = objectCenter.y - faceCenter.y
        return sqrt(dx * dx + dy * dy) <= maxDist
    }

    /// Check if any hand joint point is inside the expanded face bounding box (40% expansion each direction).
    private func isAnyHandPointNearFace(handPoints: [CGPoint], faceBox: CGRect) -> Bool {
        let expandedBox = faceBox.insetBy(dx: -faceBox.width * 0.4, dy: -faceBox.height * 0.4)
        return handPoints.contains { expandedBox.contains($0) }
    }

    /// Update rolling face area baseline using 80th percentile.
    private func updateBaseline(area: CGFloat) {
        faceAreaHistory.append(area)
        if faceAreaHistory.count > baselineWindowSize {
            faceAreaHistory.removeFirst()
        }
        guard faceAreaHistory.count >= 5 else { return }
        let sorted = faceAreaHistory.sorted()
        let idx = Int(Double(sorted.count - 1) * 0.80)
        adaptiveBaseline = sorted[idx]
    }

    /// Convert RGB (0–1) to HSV (h: 0–360, s: 0–1, v: 0–1).
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
