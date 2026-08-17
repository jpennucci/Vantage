import CoreLocation
import Foundation

/// The JSON format for "researched elsewhere, import into Vantage" — deliberately
/// plain JSON rather than a Claude-specific format, so any AI assistant (or a human
/// typing it by hand) can produce a compatible file. Supports either raw coordinates
/// or a plain address (geocoded on import), since whoever's producing the file may
/// only have one or the other.
///
/// {
///   "name": "Optional collection name",
///   "spots": [
///     { "title": "Old barn off Route 9", "latitude": 40.7128, "longitude": -74.0060,
///       "tags": ["to shoot"], "note": "Good evening light" },
///     { "title": "Alt: address instead of coordinates", "address": "123 Main St, Anytown, NY" }
///   ]
/// }
struct ImportedSpot: Codable {
    var title: String?
    var latitude: Double?
    var longitude: Double?
    var address: String?
    var tags: [String]?
    var note: String?
}

struct SpotImportFile: Codable {
    var name: String?
    var spots: [ImportedSpot]
}

enum SpotImportService {
    static func parse(_ data: Data) -> [ImportedSpot]? {
        try? JSONDecoder().decode(SpotImportFile.self, from: data).spots
    }

    /// Resolves address-only spots via geocoding; nil if a spot has neither
    /// coordinates nor a resolvable address.
    static func resolveCoordinates(for spot: ImportedSpot) async -> (latitude: Double, longitude: Double)? {
        if let lat = spot.latitude, let lng = spot.longitude {
            return (lat, lng)
        }
        guard let address = spot.address, !address.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let placemark = try? await CLGeocoder().geocodeAddressString(address).first,
              let location = placemark.location else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }
}
