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

    /// Notice shown when the selected camera was unavailable and we fell back to default
    private(set) var fallbackNotice: String?

    /// True while positive detection frames are arriving (for menu bar icon)
    private(set) var isDrinkingActive = false
    private var drinkingDeactivationTask: Task<Void, Never>?

    /// The camera uniqueID to use (nil = system default)
    private var selectedCameraID: String?

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

    func start(cameraID: String? = nil) {
        selectedCameraID = cameraID
        fallbackNotice = nil
        logger.notice("WebcamMonitor.start() called, cameraID: \(cameraID ?? "default"), status: \(self.status.rawValue)")
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

    func setDetectionAlgorithm(_ id: DetectionAlgorithmID) {
        captureDelegate.algorithm = makeDetectionAlgorithm(for: id)
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

        let cameraID = selectedCameraID
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.loadObjectDetectionModel()
            self.configureSessionOnBackground(cameraID: cameraID)
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

    private nonisolated func configureSessionOnBackground(cameraID: String?) {
        logger.notice("Configuring capture session...")

        let session = AVCaptureSession()
        session.beginConfiguration()

        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }

        // Resolve camera: selected ID → specific device, fallback → system default
        let requestedID = cameraID
        var camera: AVCaptureDevice?
        var didFallback = false

        if let requestedID {
            camera = AVCaptureDevice(uniqueID: requestedID)
            if camera == nil {
                logger.warning("Selected camera \(requestedID) not found, falling back to default")
                camera = AVCaptureDevice.default(for: .video)
                didFallback = true
            }
        } else {
            camera = AVCaptureDevice.default(for: .video)
        }

        guard let camera else {
            logger.error("No video capture device found")
            Task { @MainActor in self.setError("No camera found") }
            session.commitConfiguration()
            return
        }

        if didFallback {
            Task { @MainActor in
                self.fallbackNotice = "Selected camera unavailable — using \(camera.localizedName)"
            }
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

        // Observe camera disconnect — restart with fallback if active camera is unplugged
        let deviceDisconnectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard let device = notification.object as? AVCaptureDevice else { return }
                // Check if the disconnected device is the one we're currently using
                guard let currentInput = session.inputs.first as? AVCaptureDeviceInput,
                      currentInput.device.uniqueID == device.uniqueID else { return }
                logger.warning("Active camera disconnected: \(device.localizedName)")
                self.stop()
                self.start(cameraID: nil)  // Restart with default
                self.fallbackNotice = "\(device.localizedName) disconnected — using default camera"
            }
        }

        sessionObservers = [interruptedObserver, resumedObserver, runtimeErrorObserver, deviceDisconnectObserver]
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

    /// Pluggable detection algorithm
    var algorithm: any DetectionAlgorithm = ColorFingersAlgorithm()

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

        // Calibration mode — doesn't use algorithm
        if currentCalibrationPhase != .idle {
            handleCalibrationFrame(pixelBuffer: pixelBuffer)
            return
        }

        // Build shared input (if face present)
        let calibration = calibrationData
        guard let input = buildDetectionInput(pixelBuffer: pixelBuffer, minObjectConfidence: testingEnabled ? 0.3 : 0.4) else {
            if testingEnabled {
                let signals = DetectionSignals(
                    faceDetected: false, faceArea: 0, baseline: Float(currentBaseline),
                    handNearFace: false, colorMatchRatio: 0, colorMatchThreshold: 0.05,
                    objectNearFace: false, objectLabel: nil, objectConfidence: 0,
                    isDrinking: false, triggerReason: nil, colorMatchMask: nil
                )
                onTestingSignals?(signals)
            } else {
                onFrameAnalyzed?(false, "no face")
            }
            return
        }

        // Update adaptive baseline when no hand near face
        let handNearFace = input.handPoints.contains {
            let expandedBox = input.faceBox.insetBy(dx: -input.faceBox.width * 0.4, dy: -input.faceBox.height * 0.4)
            return expandedBox.contains($0)
        }
        if !handNearFace {
            updateBaseline(area: input.faceArea)
        }

        if testingEnabled {
            let signals = algorithm.computeTestingSignals(input: input, calibration: calibration)
            onTestingSignals?(signals)
        } else {
            let result = algorithm.analyze(input: input, calibration: calibration)

            if frameCount % 10 == 0, !result.isDrinking {
                logger.notice("\(result.logEntry, privacy: .public) (frame \(self.frameCount))")
            }

            onFrameAnalyzed?(result.isDrinking, result.logEntry)
        }
    }

    // MARK: - Input Building

    private func buildDetectionInput(pixelBuffer: CVPixelBuffer, minObjectConfidence: Float) -> DetectionInput? {
        guard let face = faceRequest.results?.first else { return nil }
        let faceBox = face.boundingBox

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
                      topLabel.confidence >= minObjectConfidence else { return nil }
                let box = obs.boundingBox
                return (CGPoint(x: box.midX, y: box.midY), topLabel.confidence, topLabel.identifier)
            }
        }()

        return DetectionInput(
            pixelBuffer: pixelBuffer,
            faceBox: faceBox,
            faceArea: faceBox.width * faceBox.height,
            faceCenter: CGPoint(x: faceBox.midX, y: faceBox.midY),
            handPoints: handPoints,
            drinkObjects: drinkObjects
        )
    }

    private var calibrationData: CalibrationData {
        CalibrationData(
            baseline: currentBaseline,
            dropThreshold: calibratedDropThreshold ?? 0.15,
            bottleHue: bottleHue,
            bottleSaturation: bottleSaturation,
            bottleHueTolerance: bottleHueTolerance,
            bottleSatTolerance: bottleSatTolerance
        )
    }

    // MARK: - Preview

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

        if currentCalibrationPhase == .drinking {
            if let color = extractDominantNonSkinColor(pixelBuffer: pixelBuffer, faceBox: face.boundingBox) {
                calibrationColorSamples.append(color)
            }
        }
    }

    // MARK: - Helpers

    private var currentBaseline: CGFloat {
        calibratedBaseline ?? adaptiveBaseline
    }

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
}
