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
    /// via Siri: "save this spot in Vantage and call it abandoned house") or edited later.
    var title: String?
    @Relationship(deleteRule: .cascade, inverse: \PhotoAsset.entry) var photos: [PhotoAsset]? = []
    var note: String?
    var weatherSummary: String?
    var tags: [String] = []
    var tripID: UUID?
    var parkingNotes: String?
    var lumenMeterReferenceID: UUID?

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
        lumenMeterReferenceID: UUID? = nil
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
        self.lumenMeterReferenceID = lumenMeterReferenceID
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
