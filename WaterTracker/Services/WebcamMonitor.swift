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
    private let requiredConsecutiveFrames = 3

    func start() {
        logger.info("WebcamMonitor.start() called, current status: \(self.status.rawValue)")
        checkPermissionAndStart()
    }

    func stop() {
        logger.info("WebcamMonitor.stop() called")
        let sessionToStop = session
        session = nil
        status = .stopped
        consecutivePositiveFrames = 0

        sessionQueue.async {
            sessionToStop?.stopRunning()
            logger.info("Session stopped")
        }
    }

    // MARK: - Permission

    private func checkPermissionAndStart() {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        logger.info("Camera authorization status: \(String(describing: authStatus.rawValue))")

        switch authStatus {
        case .authorized:
            status = .authorized
            setupAndStartSession()
        case .notDetermined:
            Task {
                logger.info("Requesting camera access...")
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                logger.info("Camera access granted: \(granted)")
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
        logger.info("Configuring capture session on background thread...")

        let session = AVCaptureSession()
        session.beginConfiguration()

        // Use a compatible preset
        if session.canSetSessionPreset(.low) {
            session.sessionPreset = .low
        } else {
            session.sessionPreset = .medium
        }

        // Find camera
        guard let camera = AVCaptureDevice.default(for: .video) else {
            logger.error("No video capture device found")
            Task { @MainActor in self.status = .error }
            session.commitConfiguration()
            return
        }
        logger.info("Camera found: \(camera.localizedName)")

        // Add input
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                logger.info("Camera input added")
            } else {
                logger.error("Cannot add camera input to session")
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

        // Add output
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(
            captureDelegate,
            queue: DispatchQueue(label: "com.lucasprim.water-tracker.webcam-frames", qos: .userInitiated)
        )

        if session.canAddOutput(output) {
            session.addOutput(output)
            logger.info("Video output added")
        } else {
            logger.error("Cannot add video output to session")
            Task { @MainActor in self.status = .error }
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()

        // Configure frame rate (5 fps)
        do {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 5)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 5)
            camera.unlockForConfiguration()
            logger.info("Camera frame rate set to 5 fps")
        } catch {
            logger.warning("Could not configure frame rate: \(error.localizedDescription)")
        }

        // Start running
        session.startRunning()
        let isRunning = session.isRunning
        logger.info("Session startRunning() called, isRunning: \(isRunning)")

        Task { @MainActor [weak self] in
            if isRunning {
                self?.session = session
                self?.status = .running
                logger.info("WebcamMonitor status set to running")
            } else {
                self?.status = .error
                logger.error("Session failed to start running")
            }
        }
    }

    // MARK: - Detection Logic

    private func handleFrameResult(isDrinking: Bool) {
        if isDrinking {
            consecutivePositiveFrames += 1
            if consecutivePositiveFrames >= requiredConsecutiveFrames {
                logger.info("Drinking detected! (3 consecutive positive frames)")
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

    private let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
    private var frameCount = 0

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCount += 1
        if frameCount == 1 {
            logger.info("First frame received from camera")
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([bodyPoseRequest])
        } catch {
            if frameCount <= 3 {
                logger.error("Vision request failed: \(error.localizedDescription)")
            }
            return
        }

        let isDrinking = analyzePoseForDrinking()
        onFrameAnalyzed?(isDrinking)
    }

    /// Detect drinking heuristic: wrist is raised near the nose/face level.
    ///
    /// In Vision's coordinate system, Y increases upward (0 = bottom, 1 = top).
    /// A drinking gesture means the wrist is at approximately the same height
    /// or above the nose, and relatively close horizontally.
    private func analyzePoseForDrinking() -> Bool {
        guard let results = bodyPoseRequest.results, let pose = results.first else {
            return false
        }

        guard let nose = try? pose.recognizedPoint(.nose),
              nose.confidence > 0.3 else {
            return false
        }

        let wrists: [VNHumanBodyPoseObservation.JointName] = [.rightWrist, .leftWrist]

        for wristName in wrists {
            guard let wrist = try? pose.recognizedPoint(wristName),
                  wrist.confidence > 0.3 else {
                continue
            }

            let verticalDiff = wrist.location.y - nose.location.y
            let horizontalDist = abs(wrist.location.x - nose.location.x)

            // Wrist is near or above nose level and within horizontal range
            if verticalDiff > -0.15 && horizontalDist < 0.20 {
                return true
            }
        }

        return false
    }
}
