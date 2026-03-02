import Foundation
import SwiftData

@Model
final class AppSettings {
    var bottleSizeMl: Double
    var dailyGoalMl: Double
    var drinkIntervalMinutes: Int

    init(
        bottleSizeMl: Double = 500,
        dailyGoalMl: Double = 2000,
        drinkIntervalMinutes: Int = 15
    ) {
        self.bottleSizeMl = bottleSizeMl
        self.dailyGoalMl = dailyGoalMl
        self.drinkIntervalMinutes = drinkIntervalMinutes
    }
}
