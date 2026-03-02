@preconcurrency import AVFoundation
import Vision
import Observation

@MainActor
@Observable
final class WebcamMonitor {
    enum CameraStatus {
        case notDetermined
        case authorized
        case denied
        case running
        case stopped
    }

    private(set) var status: CameraStatus = .notDetermined

    var onDrinkingDetected: (() -> Void)?

    private let captureDelegate = CaptureDelegate()
    private var session: AVCaptureSession?
    private var consecutivePositiveFrames = 0
    private let requiredConsecutiveFrames = 3

    func start() {
        checkPermissionAndStart()
    }

    func stop() {
        session?.stopRunning()
        session = nil
        status = .stopped
        consecutivePositiveFrames = 0
    }

    // MARK: - Permission

    private func checkPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            status = .authorized
            startSession()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    status = .authorized
                    startSession()
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

    private func startSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .low

        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            status = .denied
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(
            captureDelegate,
            queue: DispatchQueue(label: "com.lucasprim.water-tracker.webcam", qos: .userInitiated)
        )

        // Limit to ~5 fps by setting min frame duration
        if let connection = output.connection(with: .video) {
            connection.videoMinFrameDuration = CMTime(value: 1, timescale: 5)
        }

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        // Configure frame rate on the device
        do {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 5)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 5)
            camera.unlockForConfiguration()
        } catch {
            // Non-fatal: proceed with default frame rate
        }

        captureDelegate.onFrameAnalyzed = { [weak self] isDrinking in
            Task { @MainActor in
                self?.handleFrameResult(isDrinking: isDrinking)
            }
        }

        self.session = session

        let capturedSession = session
        Task.detached {
            capturedSession.startRunning()
        }
        status = .running
    }

    // MARK: - Detection Logic

    private func handleFrameResult(isDrinking: Bool) {
        if isDrinking {
            consecutivePositiveFrames += 1
            if consecutivePositiveFrames >= requiredConsecutiveFrames {
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

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([bodyPoseRequest])

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

        // Check both wrists
        let wrists: [VNHumanBodyPoseObservation.JointName] = [.rightWrist, .leftWrist]

        for wristName in wrists {
            guard let wrist = try? pose.recognizedPoint(wristName),
                  wrist.confidence > 0.3 else {
                continue
            }

            // Wrist should be near or above nose level (Y increases upward in Vision coords)
            let verticalDiff = wrist.location.y - nose.location.y
            let horizontalDist = abs(wrist.location.x - nose.location.x)

            // Wrist is within 15% vertically of the nose (above or slightly below)
            // and within 20% horizontally
            if verticalDiff > -0.15 && horizontalDist < 0.20 {
                return true
            }
        }

        return false
    }
}
