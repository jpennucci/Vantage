import CoreLocation
import Foundation
import MapKit

/// The driving route for a trip's route finder: every coordinate along the road, with
/// running distance, so found spots can be placed "at mile 612, 4 mi off route" and a
/// long route can be cut into segments small enough for one AI reply each.
struct RouteGeometry {
    let coordinates: [CLLocationCoordinate2D]
    /// Meters from the start to each coordinate.
    let cumulativeMeters: [Double]
    let polylines: [MKPolyline]

    var totalMeters: Double { cumulativeMeters.last ?? 0 }

    struct Placement {
        let alongMeters: Double
        let offRouteMeters: Double
    }

    /// Nearest point on the route to `point`. Local flat-earth math per segment — the
    /// error is negligible at the few-mile scale that matters for "how far off route".
    func place(_ point: CLLocationCoordinate2D) -> Placement? {
        guard coordinates.count >= 2 else { return nil }
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(point.latitude * .pi / 180)
        var best: Placement?
        for index in 0..<(coordinates.count - 1) {
            let a = coordinates[index], b = coordinates[index + 1]
            let ax = (a.longitude - point.longitude) * metersPerDegreeLongitude, ay = (a.latitude - point.latitude) * metersPerDegreeLatitude
            let bx = (b.longitude - point.longitude) * metersPerDegreeLongitude, by = (b.latitude - point.latitude) * metersPerDegreeLatitude
            let dx = bx - ax, dy = by - ay
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0 ? min(max(-(ax * dx + ay * dy) / lengthSquared, 0), 1) : 0
            let px = ax + t * dx, py = ay + t * dy
            let off = (px * px + py * py).squareRoot()
            if best == nil || off < best!.offRouteMeters {
                let along = cumulativeMeters[index] + t * (cumulativeMeters[index + 1] - cumulativeMeters[index])
                best = Placement(alongMeters: along, offRouteMeters: off)
            }
        }
        return best
    }

    /// The route point `meters` from the start.
    func coordinate(atMeters meters: Double) -> CLLocationCoordinate2D {
        guard let index = cumulativeMeters.firstIndex(where: { $0 >= meters }), index > 0 else {
            return meters <= 0 ? coordinates.first! : coordinates.last!
        }
        let a = coordinates[index - 1], b = coordinates[index]
        let span = cumulativeMeters[index] - cumulativeMeters[index - 1]
        let t = span > 0 ? (meters - cumulativeMeters[index - 1]) / span : 0
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// Equal-length segments of about `miles` each (the last one absorbs the remainder
    /// rather than leaving a tiny stub).
    func segments(miles: Double) -> [RouteSegment] {
        let length = miles * RouteFinderService.metersPerMile
        let count = max(1, Int((totalMeters / length).rounded()))
        let actual = totalMeters / Double(count)
        return (0..<count).map { index in
            RouteSegment(number: index + 1, startMeters: Double(index) * actual, endMeters: Double(index + 1) * actual)
        }
    }
}

struct RouteSegment: Identifiable, Hashable {
    var id: Int { number }
    /// 1-based.
    let number: Int
    let startMeters: Double
    let endMeters: Double

    func contains(_ alongMeters: Double) -> Bool {
        alongMeters >= startMeters && alongMeters <= endMeters
    }
}

enum RouteFinderService {
    static let metersPerMile = 1609.344
    static let alongRouteTag = "along route"

    private static var geometryCache: [String: RouteGeometry] = [:]

    /// Drives start → each waypoint → end with MKDirections and joins the legs.
    /// Cached per set of points, since the route finder re-renders often.
    @MainActor
    static func geometry(for route: TripRoute) async -> RouteGeometry? {
        guard let start = route.start, let end = route.end else { return nil }
        let points = [start] + route.waypoints + [end]
        let key = points.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) }.joined(separator: ">")
        if let cached = geometryCache[key] { return cached }

        var coordinates: [CLLocationCoordinate2D] = []
        var polylines: [MKPolyline] = []
        for (from, to) in zip(points, points.dropFirst()) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate))
            request.transportType = .automobile
            guard let leg = try? await MKDirections(request: request).calculate().routes.first else { return nil }
            polylines.append(leg.polyline)
            var legPoints = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: leg.polyline.pointCount)
            leg.polyline.getCoordinates(&legPoints, range: NSRange(location: 0, length: leg.polyline.pointCount))
            coordinates.append(contentsOf: coordinates.isEmpty ? legPoints : Array(legPoints.dropFirst()))
        }
        guard coordinates.count >= 2 else { return nil }

        var cumulative = [0.0]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            cumulative.append(cumulative.last! + CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)))
        }
        let geometry = RouteGeometry(coordinates: coordinates, cumulativeMeters: cumulative, polylines: polylines)
        geometryCache[key] = geometry
        return geometry
    }

    /// "Tulsa, OK"-style name for a point, for segment labels and prompts.
    static func placeName(near coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let name = [placemark.locality ?? placemark.subAdministrativeArea, placemark.administrativeArea]
            .compactMap { $0 }
            .joined(separator: ", ")
        return name.isEmpty ? nil : name
    }

    // MARK: - Prompts

    /// Step 1 (optional): ask the AI for the towns to route through, for routes a
    /// fastest-route calculation won't follow on its own (historic Route 66, a scenic
    /// byway, "the coast road").
    static func waypointPrompt(for route: TripRoute) -> String {
        """
        I'm planning a road trip from \(route.start?.name ?? "my start") to \(route.end?.name ?? "my destination")\(route.guidance.isEmpty ? "" : ". \(route.guidance)").

        List the towns or places I should route through, in driving order, so a navigation app follows this route instead of the fastest highway. Use roughly one point every 50–100 miles, and include places where the route turns onto a different road. Don't include the start or destination themselves.

        Respond with ONLY a JSON object in exactly this format — no other text before or after it:

        {
          "waypoints": [
            { "name": "Town, State", "latitude": 00.0000, "longitude": -00.0000 }
          ]
        }
        """
    }

    static func parseWaypoints(_ text: String) -> [TripPlanStart]? {
        struct Reply: Decodable {
            struct Point: Decodable { let name: String?; let latitude: Double; let longitude: Double }
            let waypoints: [Point]
        }
        let normalized = text
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
        guard let start = normalized.firstIndex(of: "{"), let end = normalized.lastIndex(of: "}"),
              let data = String(normalized[start...end]).data(using: .utf8),
              let reply = try? JSONDecoder().decode(Reply.self, from: data),
              !reply.waypoints.isEmpty else { return nil }
        return reply.waypoints.map { TripPlanStart(name: $0.name ?? "Waypoint", latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Step 2: one prompt per segment. Includes sample points along the actual road so
    /// the AI searches *this* route, not the interstate that runs near it.
    static func segmentPrompt(
        route: TripRoute,
        geometry: RouteGeometry,
        segment: RouteSegment,
        segmentCount: Int,
        fromName: String,
        toName: String,
        existingTitles: [String]
    ) -> String {
        let samples = stride(from: segment.startMeters, through: segment.endMeters, by: max((segment.endMeters - segment.startMeters) / 6, 1))
            .map { geometry.coordinate(atMeters: $0) }
            .map { String(format: "(%.4f, %.4f)", $0.latitude, $0.longitude) }
            .joined(separator: ", ")
        let interests = route.allInterests.isEmpty ? "interesting, photogenic places worth a stop" : route.allInterests.joined(separator: ", ")
        let miles = Int((segment.endMeters - segment.startMeters) / metersPerMile)
        let avoid = existingTitles.isEmpty ? "" : "\n\nI already have these, so don't repeat them: \(existingTitles.prefix(40).joined(separator: ", "))."

        return """
        I'm driving from \(route.start?.name ?? "my start") to \(route.end?.name ?? "my destination")\(route.guidance.isEmpty ? "" : " (\(route.guidance))"). Right now I'm researching segment \(segment.number) of \(segmentCount): about \(miles) miles from \(fromName) to \(toName). The route passes through approximately these points: \(samples).

        Find: \(interests).

        Only include places within about \(Int(route.maxDetourMiles)) miles of this route. I'm looking for specific, lesser-known places — the kind people mention in forums, Reddit threads, road-trip blogs, local history sites, and photography groups — not chain stores or generic tourist attractions. Search the web if you can, and only include places you have good reason to believe exist and are still there (note it if something is abandoned or on private property).

        Respond with ONLY a JSON object in exactly this format — no other text before or after it:

        {
          "name": "Segment \(segment.number): \(fromName) to \(toName)",
          "spots": [
            {
              "title": "Short descriptive name",
              "address": "Street address or nearest road and town",
              "latitude": 00.0000,
              "longitude": -00.0000,
              "tags": ["what kind of place"],
              "note": "One or two sentences on why it's worth stopping, and when the light is best if you know",
              "source": "Where this is mentioned (site or forum name)"
            }
          ]
        }

        Include both an address and coordinates for every spot — they're cross-checked on import.\(avoid)
        """
    }
}

extension RouteFinderService {
    /// A typed place for the route's start/end/waypoints (or a day's start point): a
    /// Google Maps link (keeping its place name) or anything the geocoder can find.
    static func resolvePlace(_ text: String) async -> TripPlanStart? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if GoogleMapsLinkParser.looksLikeMapsLink(trimmed), let place = await GoogleMapsLinkParser.resolvePlace(from: trimmed) {
            return TripPlanStart(name: place.name ?? "Pinned place", latitude: place.latitude, longitude: place.longitude)
        }
        guard let placemark = try? await CLGeocoder().geocodeAddressString(trimmed).first,
              let location = placemark.location else { return nil }
        let name = [placemark.locality ?? placemark.name, placemark.administrativeArea]
            .compactMap { $0 }
            .joined(separator: ", ")
        return TripPlanStart(name: name.isEmpty ? trimmed : name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}
