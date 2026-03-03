import Foundation
import SwiftData

@Model
final class AppSettings {
    var bottleSizeMl: Double
    var dailyGoalMl: Double
    var drinkIntervalMinutes: Int

    // Webcam calibration
    var calibratedBaselineQuality: Float?
    var calibratedDropThreshold: Float?
    var calibrationDate: Date?

    // Bottle color (HSV hue 0–360, saturation 0–1)
    var bottleColorHue: Float?
    var bottleColorSaturation: Float?
    var bottleColorHueTolerance: Float?     // degrees, default 15
    var bottleColorSatTolerance: Float?     // 0–1, default 0.15

    // Calibration photos (JPEG data)
    @Attribute(.externalStorage) var baselineImageData: Data?
    @Attribute(.externalStorage) var drinkingImageData: Data?

    init(
        bottleSizeMl: Double = 500,
        dailyGoalMl: Double = 2000,
        drinkIntervalMinutes: Int = 15,
        calibratedBaselineQuality: Float? = nil,
        calibratedDropThreshold: Float? = nil,
        calibrationDate: Date? = nil
    ) {
        self.bottleSizeMl = bottleSizeMl
        self.dailyGoalMl = dailyGoalMl
        self.drinkIntervalMinutes = drinkIntervalMinutes
        self.calibratedBaselineQuality = calibratedBaselineQuality
        self.calibratedDropThreshold = calibratedDropThreshold
        self.calibrationDate = calibrationDate
    }
}
