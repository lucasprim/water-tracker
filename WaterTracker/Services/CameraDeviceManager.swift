@preconcurrency import AVFoundation
import Observation
import os

private let logger = Logger(subsystem: "com.lucasprim.water-tracker", category: "CameraDeviceManager")

@MainActor
@Observable
final class CameraDeviceManager {
    private(set) var availableDevices: [AVCaptureDevice] = []

    private nonisolated(unsafe) var connectObserver: NSObjectProtocol?
    private nonisolated(unsafe) var disconnectObserver: NSObjectProtocol?

    init() {
        refreshDevices()
        connectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDevices() }
        }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDevices() }
        }
    }

    deinit {
        if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
        if let disconnectObserver { NotificationCenter.default.removeObserver(disconnectObserver) }
    }

    /// Returns the device matching the given uniqueID, or the system default if nil/not found.
    func resolveDevice(for uniqueID: String?) -> AVCaptureDevice? {
        if let uniqueID, let device = availableDevices.first(where: { $0.uniqueID == uniqueID }) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }

    /// Whether the given uniqueID matches an available device.
    func isDeviceAvailable(_ uniqueID: String?) -> Bool {
        guard let uniqueID else { return true }
        return availableDevices.contains { $0.uniqueID == uniqueID }
    }

    private func refreshDevices() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        availableDevices = session.devices
        logger.notice("Found \(self.availableDevices.count) video device(s)")
    }
}
