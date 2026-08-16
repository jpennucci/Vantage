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
        entry.tags.append(AutoTagService.timeOfDayTag(at: entry.timestamp, latitude: entry.latitude, longitude: entry.longitude))
        VantageModelContainer.shared.mainContext.insert(entry)
        NotificationCenter.default.post(name: .vantageEntrySaved, object: nil)

        // Weather and the region/motion auto-tags never block the capture itself —
        // they're fetched afterward and just fail silently offline, per the
        // offline-first architecture principle.
        let location = CLLocation(latitude: entry.latitude, longitude: entry.longitude)
        Task {
            async let weather = WeatherLookup.summary(for: location)
            async let region = AutoTagService.regionTag(for: location)
            async let motion = AutoTagService.motionTag()

            if let summary = await weather { entry.weatherSummary = summary }
            if let regionTag = await region { entry.tags.append(regionTag) }
            if let motionTag = await motion { entry.tags.append(motionTag) }

            try? VantageModelContainer.shared.mainContext.save()
        }

        return entry
    }
}
