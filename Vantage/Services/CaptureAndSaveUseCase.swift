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
        // Guards against a second tap starting an overlapping capture while the first
        // one's background weather/tag fetch is still in flight — the button stays
        // disabled (isCapturing) for that whole window, not just the GPS fix.
        guard !captureService.isCapturing else { return nil }
        captureService.isCapturing = true

        guard let entry = await captureService.captureLocation() else {
            captureService.isCapturing = false
            return nil
        }
        entry.title = title
        entry.tripID = ActiveTripStore.activeTripID
        let timeOfDayTag = AutoTagService.timeOfDayTag(at: entry.timestamp, latitude: entry.latitude, longitude: entry.longitude)
        entry.tags.append(timeOfDayTag)
        entry.autoTags.append(timeOfDayTag)
        VantageModelContainer.shared.mainContext.insert(entry)
        // Save synchronously before returning — critical for App-Intent-driven capture
        // (widget, complication, Siri), where the host process is eligible for
        // suspension the instant perform() returns. Without this, the entry could be
        // inserted in memory but killed before the background save below ever runs,
        // silently discarding the whole capture despite the intent reporting success.
        try? VantageModelContainer.shared.mainContext.save()
        NotificationCenter.default.post(name: .vantageEntrySaved, object: nil)

        // Weather and the region/motion auto-tags never block the capture itself —
        // they're fetched afterward and just fail silently offline, per the
        // offline-first architecture principle. This second save only enriches an
        // already-persisted entry, so losing it to process suspension just means the
        // entry lacks weather/tags, not that it disappears entirely.
        let location = CLLocation(latitude: entry.latitude, longitude: entry.longitude)
        Task {
            async let weather = WeatherLookup.summary(for: location)
            async let region = AutoTagService.regionTag(for: location)
            async let motion = AutoTagService.motionTag()

            if let summary = await weather { entry.weatherSummary = summary }
            if let regionTag = await region {
                entry.tags.append(regionTag)
                entry.autoTags.append(regionTag)
            }
            if let motionTag = await motion {
                entry.tags.append(motionTag)
                entry.autoTags.append(motionTag)
            }

            try? VantageModelContainer.shared.mainContext.save()
            captureService.isCapturing = false
        }

        return entry
    }
}
