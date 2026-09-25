import Foundation
import SwiftData

/// Which screen a screenshot-mode launch should open (VANTAGE_SCREENSHOT_SCREEN), and
/// a way to wait for the demo trip, which is seeded asynchronously (its pictures are
/// fetched live). Inert unless VANTAGE_SCREENSHOT_MODE=1.
enum ScreenshotScreen {
    static var current: String? {
        ScreenshotSeedData.isScreenshotMode ? ProcessInfo.processInfo.environment["VANTAGE_SCREENSHOT_SCREEN"] : nil
    }

    static func `is`(_ name: String) -> Bool { current == name }

    static func hasPrefix(_ prefix: String) -> Bool { current?.hasPrefix(prefix) == true }

    @MainActor
    static func demoTrip(in context: ModelContext) async -> TripModel? {
        for _ in 0..<60 {
            if let trip = try? context.fetch(FetchDescriptor<TripModel>()).first(where: { $0.name == ScreenshotTripSeed.tripName }) {
                return trip
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }
}
