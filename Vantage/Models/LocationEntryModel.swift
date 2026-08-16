import Foundation

/// A single scouted location. Fields beyond the MVP capture loop (photos, notes,
/// weather, tags, trip grouping) are included now so the CloudKit schema doesn't
/// need to be reshaped later — see Architecture Principles in the project spec.
struct LocationEntryModel: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let headingDegrees: Double?

    var photoReferences: [URL]
    var note: String?
    var weatherSummary: String?
    var tags: [String]
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
