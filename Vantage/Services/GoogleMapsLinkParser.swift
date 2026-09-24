import CoreLocation
import Foundation

/// Extracts coordinates from a pasted Google Maps link, for the "route planning at
/// home" workflow — paste a link found while researching in a browser, get an entry.
/// Pure URL parsing plus a plain HTTP redirect follow for shortened links; no API key
/// or billing, unlike the Google Maps JavaScript/Places APIs.
enum GoogleMapsLinkParser {
    struct Place {
        let latitude: Double
        let longitude: Double
        /// From the link's `/place/<Name>/` path segment, when it has one — pin-drop
        /// and coordinate-only links don't.
        let name: String?
    }

    /// Cheap pre-check (no network) for deciding whether pasted/dropped text is worth
    /// handing to `resolvePlace` at all.
    static func looksLikeMapsLink(_ rawText: String) -> Bool {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URL(string: trimmed)?.host?.lowercased() else { return false }
        return host.contains("goo.gl") || (host.contains("google.") && trimmed.contains("/maps"))
    }

    static func resolveCoordinates(from rawText: String) async -> (latitude: Double, longitude: Double)? {
        guard let place = await resolvePlace(from: rawText) else { return nil }
        return (place.latitude, place.longitude)
    }

    static func resolvePlace(from rawText: String) async -> Place? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: trimmed) else { return nil }

        // Shortened links (maps.app.goo.gl, goo.gl) don't carry coordinates in the URL
        // itself — resolve the redirect first to get the real, long-form URL.
        if let host = url.host, host.contains("goo.gl") {
            if let resolved = await resolveRedirect(url) {
                url = resolved
            }
        }

        let urlString = url.absoluteString
        guard let coordinate = coordinates(in: urlString) else { return nil }
        return Place(latitude: coordinate.latitude, longitude: coordinate.longitude, name: placeName(in: url))
    }

    private static func coordinates(in urlString: String) -> (latitude: Double, longitude: Double)? {
        // Embedded place data format: !3d<lat>!4d<lng> — checked first because on a
        // place link it's the pin itself, while the @lat,lng below is just the map
        // viewport's center, which can be hundreds of meters off.
        if let match = firstMatch(in: urlString, pattern: #"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)"#) {
            return match
        }
        // Most common share-link format: .../@lat,lng,zoom
        if let match = firstMatch(in: urlString, pattern: #"@(-?\d+\.\d+),(-?\d+\.\d+)"#) {
            return match
        }
        // ?q=lat,lng or ?query=lat,lng
        if let match = firstMatch(in: urlString, pattern: #"[?&](?:q|query)=(-?\d+\.\d+),(-?\d+\.\d+)"#) {
            return match
        }
        // ?ll=lat,lng
        if let match = firstMatch(in: urlString, pattern: #"[?&]ll=(-?\d+\.\d+),(-?\d+\.\d+)"#) {
            return match
        }
        return nil
    }

    /// `/maps/place/Race+Point+Lighthouse/@42.06,...` → "Race Point Lighthouse".
    private static func placeName(in url: URL) -> String? {
        let components = url.pathComponents
        guard let index = components.firstIndex(of: "place"), index + 1 < components.count else { return nil }
        let raw = components[index + 1].replacingOccurrences(of: "+", with: " ")
        let name = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name.hasPrefix("@") ? nil : name
    }

    // MARK: - Directions (routes)

    /// One stop on a shared Google Maps route, in driving order. `name` is nil for a
    /// point you dragged the route through (Google only stores its coordinates).
    struct RouteStop {
        let name: String?
        let latitude: Double
        let longitude: Double
    }

    /// Reads a shared Google Maps directions link (`/maps/dir/A/B/C/...`, or a
    /// maps.app.goo.gl short link to one) into its stops, in order — including
    /// points the route was dragged through, which is how you make it follow a
    /// particular road (historic Route 66) instead of the fastest highway.
    ///
    /// The path lists the named stops; the `data=` segment holds each stop's exact
    /// coordinates (`!1d<lng>!2d<lat>`) plus any dragged via points, in route order.
    /// Links without coordinates fall back to looking up the names.
    static func resolveDirections(from rawText: String) async -> [RouteStop]? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: trimmed) else { return nil }
        if let host = url.host, host.contains("goo.gl"), let resolved = await resolveRedirect(url) {
            url = resolved
        }
        let components = url.pathComponents
        guard let dirIndex = components.firstIndex(of: "dir") else { return nil }

        var names: [String] = []
        for component in components[(dirIndex + 1)...] {
            if component.hasPrefix("@") || component.hasPrefix("data=") { break }
            let decoded = (component.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? component)
                .trimmingCharacters(in: .whitespaces)
            // "My Location" / an empty slot means "wherever you are" — nothing to import.
            if decoded.isEmpty || ["my location", "your location", "current location"].contains(decoded.lowercased()) { continue }
            names.append(decoded)
        }

        let data = components.first { $0.hasPrefix("data=") } ?? ""
        let coordinates = allMatches(in: data, pattern: #"!1d(-?\d+\.\d+)!2d(-?\d+\.\d+)"#).map { (latitude: $0.1, longitude: $0.0) }

        if coordinates.count >= 2 {
            // Name each coordinate from the path where we can: exact match when there's
            // one coordinate per name, otherwise by looking the names up and pairing each
            // with the nearest coordinate (the extras are dragged via points).
            if coordinates.count == names.count {
                return zip(names, coordinates).map { RouteStop(name: $0, latitude: $1.latitude, longitude: $1.longitude) }
            }
            var labels = [String?](repeating: nil, count: coordinates.count)
            for name in names {
                guard let found = await geocode(name) else { continue }
                let nearest = coordinates.indices
                    .filter { labels[$0] == nil }
                    .min { distanceSquared(coordinates[$0], found) < distanceSquared(coordinates[$1], found) }
                if let nearest, distanceSquared(coordinates[nearest], found) < 0.05 * 0.05 {
                    labels[nearest] = name
                }
            }
            return coordinates.indices.map { RouteStop(name: labels[$0], latitude: coordinates[$0].latitude, longitude: coordinates[$0].longitude) }
        }

        // No coordinates in the link: each path entry is a name (or a "lat,lng").
        var stops: [RouteStop] = []
        for name in names {
            if let pair = firstMatch(in: name, pattern: #"^(-?\d+\.\d+),\s*(-?\d+\.\d+)$"#) {
                stops.append(RouteStop(name: nil, latitude: pair.latitude, longitude: pair.longitude))
            } else if let found = await geocode(name) {
                stops.append(RouteStop(name: name, latitude: found.latitude, longitude: found.longitude))
            }
        }
        return stops.count >= 2 ? stops : nil
    }

    static func looksLikeDirectionsLink(_ rawText: String) -> Bool {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("/maps/dir/") || (looksLikeMapsLink(trimmed) && trimmed.contains("goo.gl"))
    }

    private static func geocode(_ text: String) async -> (latitude: Double, longitude: Double)? {
        guard let location = try? await CLGeocoder().geocodeAddressString(text).first?.location else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }

    private static func distanceSquared(_ a: (latitude: Double, longitude: Double), _ b: (latitude: Double, longitude: Double)) -> Double {
        let dLat = a.latitude - b.latitude, dLng = a.longitude - b.longitude
        return dLat * dLat + dLng * dLng
    }

    /// All `(first, second)` number pairs matching `pattern`'s two capture groups.
    private static func allMatches(in string: String, pattern: String) -> [(Double, Double)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: string, range: NSRange(string.startIndex..., in: string)).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let r1 = Range(match.range(at: 1), in: string), let r2 = Range(match.range(at: 2), in: string),
                  let first = Double(string[r1]), let second = Double(string[r2]) else { return nil }
            return (first, second)
        }
    }

    private static func resolveRedirect(_ url: URL) async -> URL? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response.url
        } catch {
            return nil
        }
    }

    private static func firstMatch(in string: String, pattern: String) -> (latitude: Double, longitude: Double)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              match.numberOfRanges >= 3,
              let latRange = Range(match.range(at: 1), in: string),
              let lngRange = Range(match.range(at: 2), in: string),
              let latitude = Double(string[latRange]),
              let longitude = Double(string[lngRange]) else { return nil }
        return (latitude, longitude)
    }
}
