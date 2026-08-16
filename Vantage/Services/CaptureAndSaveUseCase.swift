import CoreLocation
import SwiftData

extension Notification.Name {
    /// Posted after a successful capture, regardless of entry point (in-app button,
    /// Lock Screen widget, or Siri) — lets any visible screen show a save confirmation.
    static let vantageEntrySaved = Notification.Name("vantageEntrySaved")
}

/// Shared by the in-app capture button, the Lock Screen widget button, and the
/// Siri Shortcut so all three entry points save through the exact same path.
@MainActor
enum CaptureAndSaveUseCase {
    @discardableResult
    static func run(using captureService: LocationCaptureService, title: String? = nil) async -> LocationEntryModel? {
        guard let entry = await captureService.captureLocation() else { return nil }
        entry.title = title
        entry.tripID = ActiveTripStore.activeTripID
        VantageModelContainer.shared.mainContext.insert(entry)
        NotificationCenter.default.post(name: .vantageEntrySaved, object: nil)

        // Weather never blocks the capture itself — it's fetched afterward and just
        // fails silently offline, per the offline-first architecture principle.
        let location = CLLocation(latitude: entry.latitude, longitude: entry.longitude)
        Task {
            guard let summary = await WeatherLookup.summary(for: location) else { return }
            entry.weatherSummary = summary
            try? VantageModelContainer.shared.mainContext.save()
        }

        return entry
    }
}
