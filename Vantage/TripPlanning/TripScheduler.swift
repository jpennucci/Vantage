import CoreLocation
import MapKit

/// Day-schedule math shared by the Mac Trip Planner and the iPhone itinerary, so both
/// show the same arrival times: leave the start (or arrive at the first stop when
/// there's no start) at the day's start time, then drive time + time at each stop.
enum TripScheduler {
    /// The plan day's date moved `days` later, for a stop reached after midnight.
    static func date(_ day: TripDayPlan, plus days: Int) -> Date {
        days == 0 ? day.date : Calendar.current.date(byAdding: .day, value: days, to: day.date) ?? day.date
    }

    static func coordinate(_ entry: LocationEntryModel) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude)
    }

    static func stops(for day: TripDayPlan, in entries: [LocationEntryModel]) -> [LocationEntryModel] {
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return day.stopIDs.compactMap { byID[$0] }
    }

    /// A leg still being calculated counts as zero until it arrives. `sun` is given
    /// the stop and how many days after the plan day it's reached (usually 0), so each
    /// stop is judged against the sunrise/sunset of the day you actually get there.
    static func schedule(
        for day: TripDayPlan,
        stops: [LocationEntryModel],
        legs: [String: TripPlanLeg],
        timeZone: TimeZone,
        sun: (LocationEntryModel, Int) -> TripPlanSunDay
    ) -> [TripScheduleItem] {
        let midnight = TripPlanning.dayStart(day.date, in: timeZone)
        var clock = midnight.addingTimeInterval(day.startMinute * 60)
        var previous: CLLocationCoordinate2D? = day.start?.coordinate
        var items: [TripScheduleItem] = []
        for entry in stops {
            let here = coordinate(entry)
            let leg = previous.flatMap { legs[TripPlanLeg.key($0, here)] }
            let arrival = clock.addingTimeInterval(leg?.travelTime ?? 0)
            let departure = arrival.addingTimeInterval(day.minutesPerStop * 60)
            let offset = max(0, Int(floor(arrival.timeIntervalSince(midnight) / 86_400)))
            items.append(TripScheduleItem(entry: entry, legFromPrevious: leg, arrival: arrival, departure: departure, sun: sun(entry, offset), dayOffset: offset))
            clock = departure
            previous = here
        }
        return items
    }

    /// Every driving leg a day needs, start point first.
    static func legPairs(for day: TripDayPlan, stops: [LocationEntryModel]) -> [(CLLocationCoordinate2D, CLLocationCoordinate2D)] {
        var points = stops.map(coordinate)
        if let start = day.start { points.insert(start.coordinate, at: 0) }
        return Array(zip(points, points.dropFirst()))
    }

    /// Sequential rather than concurrent — MKDirections throttles apps that fire off a
    /// burst of requests. Skips pairs already in `existing`.
    @MainActor
    static func calculateLegs(
        _ pairs: [(CLLocationCoordinate2D, CLLocationCoordinate2D)],
        skipping existing: [String: TripPlanLeg],
        found: (String, TripPlanLeg) -> Void
    ) async {
        for (from, to) in pairs {
            let key = TripPlanLeg.key(from, to)
            guard existing[key] == nil else { continue }
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
            request.transportType = .automobile
            guard let route = try? await MKDirections(request: request).calculate().routes.first else { continue }
            if Task.isCancelled { return }
            found(key, TripPlanLeg(travelTime: route.expectedTravelTime, distance: route.distance, polyline: route.polyline))
        }
    }

    static func routeURL(for day: TripDayPlan, stops: [LocationEntryModel]) -> URL? {
        var points = stops.map { (latitude: $0.latitude, longitude: $0.longitude) }
        if let start = day.start {
            points.insert((latitude: start.latitude, longitude: start.longitude), at: 0)
        }
        guard points.count >= 2 else { return nil }
        return ExternalNavigationService.googleMapsRouteURL(stops: points)
    }
}
