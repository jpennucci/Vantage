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

    var photoReferences: [URL] = []
    var note: String?
    var weatherSummary: String?
    var tags: [String] = []
    var tripID: UUID?
    var vanTrailerNotes: String?
    var lumenMeterReferenceID: UUID?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        latitude: Double,
        longitude: Double,
        headingDegrees: Double? = nil,
        photoReferences: [URL] = [],
        note: String? = nil,
        weatherSummary: String? = nil,
        tags: [String] = [],
        tripID: UUID? = nil,
        vanTrailerNotes: String? = nil,
        lumenMeterReferenceID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.headingDegrees = headingDegrees
        self.photoReferences = photoReferences
        self.note = note
        self.weatherSummary = weatherSummary
        self.tags = tags
        self.tripID = tripID
        self.vanTrailerNotes = vanTrailerNotes
        self.lumenMeterReferenceID = lumenMeterReferenceID
    }
}
