import Foundation
import SwiftData

/// A single scouted location. Fields beyond the MVP capture loop (photos, notes,
/// weather, tags, trip grouping) are included now so the CloudKit schema doesn't
/// need to be reshaped later — see Architecture Principles in the project spec.
///
/// All properties have default values and none are marked `.unique`, since SwiftData's
/// CloudKit sync (step 14 in the build order) requires that of every attribute.
@Model
final class LocationEntryModel {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var latitude: Double = 0
    var longitude: Double = 0
    var headingDegrees: Double?

    /// Short display name, e.g. "abandoned house" — settable at capture time (including
    /// via Siri: "save this spot in Photo Point and call it abandoned house") or edited later.
    var title: String?
    @Relationship(deleteRule: .cascade, inverse: \PhotoAsset.entry) var photos: [PhotoAsset]? = []
    var note: String?
    var weatherSummary: String?
    var tags: [String] = []
    /// Which entries in `tags` were applied automatically (time-of-day, region,
    /// motion) rather than typed by hand — lets the UI color them consistently even
    /// though region tags are dynamic place names with no fixed vocabulary to match
    /// against, unlike the starter suggestions.
    var autoTags: [String] = []
    var tripID: UUID?
    var parkingNotes: String?
    var parkingLatitude: Double?
    var parkingLongitude: Double?
    /// LumenMeter roll ID (e.g. "LM-A3F9K2") — LumenMeter's own roll IDs are short
    /// strings, not UUIDs, matching the format of the roll's own QR code payload.
    var lumenMeterRollID: String?
    var shotList: [ShotListItem] = []

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        latitude: Double,
        longitude: Double,
        headingDegrees: Double? = nil,
        title: String? = nil,
        note: String? = nil,
        weatherSummary: String? = nil,
        tags: [String] = [],
        tripID: UUID? = nil,
        parkingNotes: String? = nil,
        parkingLatitude: Double? = nil,
        parkingLongitude: Double? = nil,
        lumenMeterRollID: String? = nil,
        shotList: [ShotListItem] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.headingDegrees = headingDegrees
        self.title = title
        self.note = note
        self.weatherSummary = weatherSummary
        self.tags = tags
        self.tripID = tripID
        self.parkingNotes = parkingNotes
        self.parkingLatitude = parkingLatitude
        self.parkingLongitude = parkingLongitude
        self.lumenMeterRollID = lumenMeterRollID
        self.shotList = shotList
    }
}

extension LocationEntryModel {
    var goldenHourSuggestion: SunPositionEngine.GoldenHourSuggestion? {
        guard let heading = headingDegrees else { return nil }
        return SunPositionEngine.goldenHourSuggestion(
            headingDegrees: heading,
            near: Date(),
            latitude: latitude,
            longitude: longitude
        )
    }
}
