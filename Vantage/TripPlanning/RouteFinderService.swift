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
    /// Apple Maps' driving time for the whole route, for drive-time budgeting.
    var totalSeconds: Double = 0

    var totalMeters: Double { cumulativeMeters.last ?? 0 }

    /// Driving seconds for a stretch of route, at the route's own average speed.
    func seconds(forMeters meters: Double) -> Double {
        guard totalMeters > 0 else { return 0 }
        return meters / totalMeters * totalSeconds
    }

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
        var seconds = 0.0
        for (from, to) in zip(points, points.dropFirst()) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate))
            request.transportType = .automobile
            guard let leg = try? await MKDirections(request: request).calculate().routes.first else { return nil }
            polylines.append(leg.polyline)
            seconds += leg.expectedTravelTime
            var legPoints = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: leg.polyline.pointCount)
            leg.polyline.getCoordinates(&legPoints, range: NSRange(location: 0, length: leg.polyline.pointCount))
            coordinates.append(contentsOf: coordinates.isEmpty ? legPoints : Array(legPoints.dropFirst()))
        }
        guard coordinates.count >= 2 else { return nil }

        var cumulative = [0.0]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            cumulative.append(cumulative.last! + CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)))
        }
        let geometry = RouteGeometry(coordinates: coordinates, cumulativeMeters: cumulative, polylines: polylines, totalSeconds: seconds)
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

        Never put double-quote characters (") inside a name — write it as plain text.
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
        guard let start = normalized.firstIndex(of: "{"), let end = normalized.lastIndex(of: "}") else { return nil }
        let object = String(normalized[start...end])
        let decoded = object.data(using: .utf8).flatMap { try? JSONDecoder().decode(Reply.self, from: $0) }
            ?? SpotImportService.repairUnescapedQuotes(in: object).data(using: .utf8).flatMap { try? JSONDecoder().decode(Reply.self, from: $0) }
        guard let reply = decoded, !reply.waypoints.isEmpty else { return nil }
        return reply.waypoints.map { TripPlanStart(name: $0.name ?? "Waypoint", latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// A named point along the route, for prompts — AI tools search by town far
    /// better than by coordinates.
    struct Checkpoint {
        let mile: Int
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    /// Named checkpoints every ~`everyMiles` from `startMeters` to `endMeters`
    /// (inclusive), skipping repeats of the same town. Sequential — reverse geocoding
    /// is rate limited — and cached, so re-copying a prompt is instant.
    @MainActor
    static func checkpoints(on geometry: RouteGeometry, from startMeters: Double, to endMeters: Double, everyMiles: Double = 20) async -> [Checkpoint] {
        let span = endMeters - startMeters
        let count = max(2, Int((span / metersPerMile / everyMiles).rounded()) + 1)
        var result: [Checkpoint] = []
        for index in 0..<count {
            let meters = startMeters + span * Double(index) / Double(count - 1)
            let coordinate = geometry.coordinate(atMeters: meters)
            let key = String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
            let name: String?
            if let cached = placeNameCache[key] {
                name = cached
            } else {
                name = await placeName(near: coordinate)
                placeNameCache[key] = name
            }
            guard let name, result.last?.name != name else { continue }
            result.append(Checkpoint(mile: Int(meters / metersPerMile), name: name, coordinate: coordinate))
        }
        return result
    }

    private static var placeNameCache: [String: String?] = [:]

    /// Step 2: one prompt per stretch of road — a whole segment, or a gap in one that
    /// came back empty. Framed around checkpoint towns along *this* stretch only (not
    /// the trip's endpoints, which the AI otherwise anchors on), with an explicit ask
    /// to spread finds across every checkpoint rather than cluster near one well-known
    /// town. Replies list spots in driving order.
    static func stretchPrompt(
        route: TripRoute,
        checkpoints: [Checkpoint],
        startMeters: Double,
        endMeters: Double,
        label: String,
        existingTitles: [String]
    ) -> String {
        let miles = max(1, Int((endMeters - startMeters) / metersPerMile))
        let target = max(4, min(20, miles / 12))
        let interests = route.allInterests.isEmpty ? "interesting, photogenic places worth a stop" : route.allInterests.joined(separator: "; ")
        let checkpointLines = checkpoints
            .map { String(format: "- Mile %d: %@ (%.4f, %.4f)", $0.mile, $0.name, $0.coordinate.latitude, $0.coordinate.longitude) }
            .joined(separator: "\n")
        let from = checkpoints.first?.name ?? "the start of this stretch"
        let to = checkpoints.last?.name ?? "the end of this stretch"
        let avoid = existingTitles.isEmpty ? "" : "\n\nI already have these, so don't repeat them: \(existingTitles.prefix(40).joined(separator: ", "))."

        return """
        I'm researching one stretch of a road trip: about \(miles) miles from \(from) to \(to).\(route.guidance.isEmpty ? "" : " Route notes: \(route.guidance)") I want stops spread along this ENTIRE stretch — not clustered at one end or around one well-known town.

        Checkpoints along the route, in driving order:
        \(checkpointLines)

        What I'm looking for: \(interests).

        For each checkpoint, find 1–3 places within about \(Int(route.maxDetourMiles)) miles of the route near it. Skip a checkpoint only if there's genuinely nothing there, and aim for about \(target) places in total across the whole stretch. Prefer specific, lesser-known places — the kind people mention in forums, Reddit threads, road-trip blogs, local history sites, and photography groups — not chain stores or generic tourist attractions. Search the web if you can, and only include places you have good reason to believe exist and are still there (say so if something is abandoned or on private property).

        Respond with ONLY a JSON object in exactly this format — no other text before or after it — listing spots in driving order:

        {
          "name": "\(label)",
          "spots": [
            {
              "title": "Short descriptive name",
              "mile": 0,
              "address": "Street address, or nearest road and town",
              "latitude": 00.0000,
              "longitude": -00.0000,
              "tags": ["what kind of place"],
              "note": "One or two sentences on why it's worth stopping, and when the light is best if you know",
              "source": "Where this is mentioned (site or forum name)",
              "source_url": "Link to that page",
              "image_url": "Direct link to a photo of the place (a .jpg or .png URL from a page you found), or omit if you don't have a real one"
            }
          ]
        }

        "mile" is the approximate mile from the checkpoints above. Include both an address and coordinates for every spot — they're cross-checked on import. Never put double-quote characters (") inside any value (title, note, address, source) — not even escaped, since backslashes get lost when a reply is copied out of a chat window. Write quoted nicknames or phrases as plain text instead (Super 66 Service Station, not Super "66" Service Station).\(avoid)
        """
    }

    /// Stretches of a segment longer than `minimumMiles` with no finds at all —
    /// where the AI didn't look (or clustered elsewhere), worth a targeted re-ask.
    static func gaps(in segment: RouteSegment, findsAlongMeters: [Double], minimumMiles: Double) -> [(start: Double, end: Double)] {
        let inside = findsAlongMeters.filter { segment.contains($0) }.sorted()
        let edges = [segment.startMeters] + inside + [segment.endMeters]
        return zip(edges, edges.dropFirst())
            .filter { ($1 - $0) / metersPerMile >= minimumMiles }
            .map { (start: $0, end: $1) }
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
