@preconcurrency import AVFoundation
import Vision
import Observation
import os

private let logger = Logger(subsystem: "com.lucasprim.water-tracker", category: "WebcamMonitor")

@MainActor
@Observable
final class WebcamMonitor {
    enum CameraStatus: String {
        case notDetermined
        case authorized
        case denied
        case running
        case stopped
        case error
    }

    private(set) var status: CameraStatus = .notDetermined

    var onDrinkingDetected: (() -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.lucasprim.water-tracker.webcam-session")
    private let captureDelegate = CaptureDelegate()
    private var session: AVCaptureSession?
    private var consecutivePositiveFrames = 0
    private let requiredConsecutiveFrames = 2

    func start() {
        logger.notice("WebcamMonitor.start() called, current status: \(self.status.rawValue)")
        checkPermissionAndStart()
    }

    func stop() {
        logger.notice("WebcamMonitor.stop() called")
        let sessionToStop = session
        session = nil
        status = .stopped
        consecutivePositiveFrames = 0

        sessionQueue.async {
            sessionToStop?.stopRunning()
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
                logger.notice("Camera access granted: \(granted)")
                if granted {
                    status = .authorized
                    setupAndStartSession()
                } else {
                    status = .denied
                }
            }
        case .denied, .restricted:
            logger.warning("Camera access denied or restricted")
            status = .denied
        @unknown default:
            status = .denied
        }
    }

    // MARK: - Capture Session

    private func setupAndStartSession() {
        captureDelegate.onFrameAnalyzed = { [weak self] isDrinking in
            Task { @MainActor in
                self?.handleFrameResult(isDrinking: isDrinking)
            }
        }

        sessionQueue.async { [weak self] in
            self?.configureSessionOnBackground()
        }
    }

    private nonisolated func configureSessionOnBackground() {
        logger.notice("Configuring capture session...")

        let session = AVCaptureSession()
        session.beginConfiguration()

        // VGA for reliable face/hand detection
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }

        guard let camera = AVCaptureDevice.default(for: .video) else {
            logger.error("No video capture device found")
            Task { @MainActor in self.status = .error }
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                logger.error("Cannot add camera input")
                Task { @MainActor in self.status = .error }
                session.commitConfiguration()
                return
            }
        } catch {
            logger.error("Failed to create camera input: \(error.localizedDescription)")
            Task { @MainActor in self.status = .error }
            session.commitConfiguration()
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(
            captureDelegate,
            queue: DispatchQueue(label: "com.lucasprim.water-tracker.webcam-frames", qos: .userInitiated)
        )

        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            logger.error("Cannot add video output")
            Task { @MainActor in self.status = .error }
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()

        // 5 fps to save resources
        do {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 5)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 5)
            camera.unlockForConfiguration()
        } catch {
            logger.warning("Could not set frame rate: \(error.localizedDescription)")
        }

        session.startRunning()
        let isRunning = session.isRunning
        logger.notice("Session started, isRunning: \(isRunning), preset: \(session.sessionPreset.rawValue)")

        Task { @MainActor [weak self] in
            if isRunning {
                self?.session = session
                self?.status = .running
            } else {
                self?.status = .error
            }
        }
    }

    // MARK: - Detection Logic

    private func handleFrameResult(isDrinking: Bool) {
        if isDrinking {
            consecutivePositiveFrames += 1
            if consecutivePositiveFrames >= requiredConsecutiveFrames {
                logger.notice("Drinking detected! (\(self.requiredConsecutiveFrames) consecutive frames)")
                consecutivePositiveFrames = 0
                onDrinkingDetected?()
            }
        } else {
            consecutivePositiveFrames = 0
        }
    }
}

// MARK: - Capture Delegate

private final class CaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onFrameAnalyzed: ((Bool) -> Void)?

    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let handRequest = VNDetectHumanHandPoseRequest()
    private var frameCount = 0
    private var lastLogFrame = 0

    override init() {
        handRequest.maximumHandCount = 2
        super.init()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCount += 1
        if frameCount == 1 {
            logger.notice("First frame received from camera")
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([faceRequest, handRequest])
        } catch {
            return
        }

        let isDrinking = detectDrinkingGesture()
        onFrameAnalyzed?(isDrinking)
    }

    /// Detect drinking by checking if a hand wrist is near or overlapping the face region.
    ///
    /// Uses face rectangle + hand pose wrist position. When someone brings a
    /// bottle/glass to their mouth, the wrist overlaps or is very close to
    /// the face bounding box.
    private func detectDrinkingGesture() -> Bool {
        guard let faces = faceRequest.results, let face = faces.first else {
            logPeriodically("No face detected")
            return false
        }

        guard let hands = handRequest.results, !hands.isEmpty else {
            logPeriodically("Face detected, no hands")
            return false
        }

        // Face bounding box (normalized 0-1 coordinates, origin at bottom-left)
        let faceBox = face.boundingBox

        // Expand the face region to catch hands near the face (drinking zone)
        // Expand more downward (for chin/mouth area) and to the sides
        let expandX: CGFloat = faceBox.width * 0.5
        let expandUp: CGFloat = faceBox.height * 0.3
        let expandDown: CGFloat = faceBox.height * 0.5
        let drinkZone = CGRect(
            x: faceBox.minX - expandX,
            y: faceBox.minY - expandDown,
            width: faceBox.width + expandX * 2,
            height: faceBox.height + expandUp + expandDown
        )

        for hand in hands {
            // Get wrist position
            guard let wrist = try? hand.recognizedPoint(.wrist),
                  wrist.confidence > 0.3 else {
                continue
            }

            let wristPoint = wrist.location

            if drinkZone.contains(wristPoint) {
                logPeriodically("MATCH: wrist at (\(String(format: "%.2f", wristPoint.x)),\(String(format: "%.2f", wristPoint.y))) in drink zone \(String(format: "(%.2f,%.2f)-(%.2f,%.2f)", drinkZone.minX, drinkZone.minY, drinkZone.maxX, drinkZone.maxY))")
                return true
            }

            // Also check middle finger MCP (base of middle finger) —
            // when holding a bottle, this joint is often closer to the face
            if let middleMCP = try? hand.recognizedPoint(.middleMCP),
               middleMCP.confidence > 0.3,
               drinkZone.contains(middleMCP.location) {
                logPeriodically("MATCH: middleMCP near face")
                return true
            }
        }

        logPeriodically("Face + hands, no overlap. Face=(\(String(format: "%.2f,%.2f", faceBox.midX, faceBox.midY))) wrists=\(hands.compactMap { try? $0.recognizedPoint(.wrist) }.map { "(\(String(format: "%.2f,%.2f", $0.location.x, $0.location.y)))" }.joined(separator: ","))")
        return false
    }

    private func logPeriodically(_ message: String) {
        if frameCount - lastLogFrame >= 25 {
            lastLogFrame = frameCount
            logger.notice("\(message) (frame \(self.frameCount))")
        }
    }
}
