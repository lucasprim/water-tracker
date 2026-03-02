import AppKit
import os

private let logger = Logger(subsystem: "com.lucasprim.water-tracker", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("applicationDidFinishLaunching")
    }
}
