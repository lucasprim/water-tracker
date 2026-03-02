import Foundation
import SwiftData

@Model
final class WaterEntry {
    var volumeMl: Double
    var timestamp: Date
    var source: EntrySource

    init(volumeMl: Double, source: EntrySource = .manual) {
        self.volumeMl = volumeMl
        self.timestamp = .now
        self.source = source
    }
}
