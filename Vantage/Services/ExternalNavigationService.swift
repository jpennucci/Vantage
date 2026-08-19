import Foundation

/// Free, no-API-key deep links to external navigation apps — for handing a spot off
/// to whatever the user actually drives with.
enum ExternalNavigationService {
    /// Waze only supports single-destination navigation via its URL scheme — no
    /// multi-stop route API, unlike Google Maps below.
    static func wazeURL(latitude: Double, longitude: Double) -> URL? {
        URL(string: "waze://?ll=\(latitude),\(longitude)&navigate=yes")
    }

    /// Google Maps supports a free multi-stop route URL (no API key) — this is how
    /// "add these spots as stops on a route" gets built, since Waze can't do it.
    static func googleMapsRouteURL(stops: [(latitude: Double, longitude: Double)]) -> URL? {
        guard let last = stops.last else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(last.latitude),\(last.longitude)"),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        let waypoints = stops.dropLast().map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")
        if !waypoints.isEmpty {
            items.append(URLQueryItem(name: "waypoints", value: waypoints))
        }
        components?.queryItems = items
        return components?.url
    }

    /// Shadowmap has no official app URL scheme, just a plain web app that reads
    /// its view state straight from query params (confirmed by inspecting the URL
    /// it produces when panning to a location) — lat/lng/zoom is enough; it defaults
    /// to the current date and time, which is what scouting for today's light needs.
    static func shadowMapURL(latitude: Double, longitude: Double) -> URL? {
        URL(string: "https://app.shadowmap.org/?lat=\(latitude)&lng=\(longitude)&zoom=17")
    }

    /// Cloud-cover/visibility forecast — a landscape-photography staple for judging
    /// whether the sky will actually cooperate for golden hour, distinct from the
    /// current-conditions-only WeatherKit summary already shown at capture time.
    /// No API key needed; confirmed by inspecting the URL it produces when searching
    /// a location (path segment repeats the query params windy uses to center/zoom).
    static func windyURL(latitude: Double, longitude: Double) -> URL? {
        URL(string: "https://www.windy.com/\(latitude)/\(longitude)?\(latitude),\(longitude),12")
    }
}
