import CoreLocation
import Foundation

/// Drafts a trip's day-by-day plan from its route, its spots, and its travel settings
/// (TripSettings, from the trip wizard). A starting point to edit, not a final answer:
/// everything it produces is an ordinary TripPlan the planner/itinerary can change.
///
/// - **Straight there**: no stops — how many days the drive takes at the daily limit,
///   and roughly where each day ends.
/// - **Stop when tired**: the same days, but each ends with a few *options* for the
///   night along the last stretch, since you'll stop when you're done, not at a pin.
/// - **Plan stops**: the trip's spots, in route order, filled into days up to the
///   daily driving limit; each night ends near the day's last stop. Spots that don't
///   fit the trip's length are left for Not Scheduled, with the reason in the summary.
enum ItineraryBuilder {
    struct Result {
        let plan: TripPlan
        let summary: String
    }

    enum Failure: Error {
        case needsRoute
        case routeUnavailable
    }

    /// Longest day, driving plus stops, before a new day is started regardless.
    private static let maximumActiveHours = 13.0

    @MainActor
    static func build(trip: TripModel, entries: [LocationEntryModel], settings: TripSettings) async -> Result? {
        let route = trip.route
        guard route.hasEnds else { return nil }
        guard let geometry = await RouteFinderService.geometry(for: route), geometry.totalSeconds > 0 else { return nil }
        let timeZone = await self.timeZone(near: route.start?.coordinate) ?? .current
        let dayLimitSeconds = max(settings.maxDriveHours, 1) * 3600

        var days: [TripDayPlan] = []
        var skipped: [String] = []

        switch settings.style {
        case .straight, .whenTired:
            let dayCount = max(1, Int(ceil(geometry.totalSeconds / dayLimitSeconds)))
            var start = route.start
            for index in 0..<dayCount {
                var day = makeDay(index: index, settings: settings, start: start)
                if index < dayCount - 1 {
                    let endMeters = geometry.totalMeters * Double(index + 1) / Double(dayCount)
                    if settings.style == .straight {
                        let overnight = await place(on: geometry, atMeters: endMeters, prefix: "Overnight near")
                        day.overnightOptions = [overnight]
                        start = overnight
                    } else {
                        // Options across the last ~2 hours of the day's driving.
                        let dayMeters = geometry.totalMeters / Double(dayCount)
                        var options: [TripPlanStart] = []
                        for fraction in [0.75, 0.88, 1.0] {
                            let meters = endMeters - dayMeters * (1 - fraction)
                            let option = await place(on: geometry, atMeters: meters, prefix: "Stop near")
                            if !options.contains(where: { $0.name == option.name }) { options.append(option) }
                        }
                        day.overnightOptions = options
                        start = options.last
                    }
                }
                days.append(day)
            }

        case .planStops:
            let stops = entries
                .compactMap { entry -> (entry: LocationEntryModel, placement: RouteGeometry.Placement)? in
                    geometry.place(CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude)).map { (entry, $0) }
                }
                .sorted { $0.placement.alongMeters < $1.placement.alongMeters }

            var day = makeDay(index: 0, settings: settings, start: route.start)
            var driveSeconds = 0.0
            var activeSeconds = 0.0
            var previousAlong = 0.0
            var lastStop: LocationEntryModel?

            for stop in stops {
                let along = max(stop.placement.alongMeters, previousAlong)
                // Road time since the last stop, plus there-and-back off the route.
                let leg = geometry.seconds(forMeters: along - previousAlong) + geometry.seconds(forMeters: stop.placement.offRouteMeters * 2)
                let visit = settings.minutesPerStop * 60
                let overLimit = driveSeconds + leg > dayLimitSeconds || activeSeconds + leg + visit > maximumActiveHours * 3600
                if overLimit, !day.stopIDs.isEmpty {
                    let overnight = await overnightPlace(after: lastStop, geometry: geometry, atMeters: previousAlong)
                    day.overnightOptions = [overnight]
                    days.append(day)
                    day = makeDay(index: days.count, settings: settings, start: overnight)
                    driveSeconds = 0
                    activeSeconds = 0
                }
                if let limit = settings.dayLimit, days.count >= limit {
                    skipped.append(stop.entry.title ?? "a spot")
                    continue
                }
                day.stopIDs.append(stop.entry.id)
                driveSeconds += leg
                activeSeconds += leg + visit
                previousAlong = along
                lastStop = stop.entry
            }

            // The rest of the drive to the destination, split into more days if needed.
            var remaining = geometry.seconds(forMeters: geometry.totalMeters - previousAlong)
            if settings.dayLimit.map({ days.count < $0 }) ?? true {
                while driveSeconds + remaining > dayLimitSeconds, settings.dayLimit.map({ days.count + 1 < $0 }) ?? true {
                    let available = max(dayLimitSeconds - driveSeconds, 0)
                    let meters = previousAlong + geometry.totalMeters * (available / geometry.totalSeconds)
                    let overnight = await place(on: geometry, atMeters: meters, prefix: "Overnight near")
                    day.overnightOptions = [overnight]
                    days.append(day)
                    day = makeDay(index: days.count, settings: settings, start: overnight)
                    remaining -= available
                    previousAlong = meters
                    driveSeconds = 0
                }
                days.append(day)
            }
        }

        // Aim each day's start at morning light when that's what the trip is for.
        if settings.light == .sunrise || settings.light == .both {
            for index in days.indices {
                guard let firstID = days[index].stopIDs.first,
                      let first = entries.first(where: { $0.id == firstID }) else { continue }
                let sun = TripPlanSunDay(latitude: first.latitude, longitude: first.longitude, day: days[index].date, timeZone: timeZone, headingDegrees: first.headingDegrees)
                guard let sunrise = sun.sunrise else { continue }
                let target = sun.bestLight.flatMap { $0 < (sun.morningGoldenEnd ?? $0) ? $0 : nil } ?? sunrise
                var driveToFirst = 0.0
                if let start = days[index].start,
                   let startPlace = geometry.place(start.coordinate),
                   let firstPlace = geometry.place(CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)) {
                    driveToFirst = geometry.seconds(forMeters: abs(firstPlace.alongMeters - startPlace.alongMeters) + firstPlace.offRouteMeters)
                }
                let leave = target.addingTimeInterval(-15 * 60 - driveToFirst)
                let minutes = leave.timeIntervalSince(TripPlanning.dayStart(days[index].date, in: timeZone)) / 60
                days[index].startMinute = min(max(minutes, 3 * 60), 11 * 60)
            }
        }

        var plan = trip.plan ?? TripPlan()
        plan.days = days
        plan.settings = settings

        let driveHours = geometry.totalSeconds / 3600
        var summary = "\(days.count) day\(days.count == 1 ? "" : "s"), about \(Int(driveHours.rounded())) hours of driving (\(Int(geometry.totalMeters / RouteFinderService.metersPerMile).formatted()) miles) at up to \(Int(settings.maxDriveHours)) hours a day."
        if settings.style == .planStops {
            let placed = days.reduce(0) { $0 + $1.stopIDs.count }
            summary += " \(placed) stop\(placed == 1 ? "" : "s") placed."
            if !skipped.isEmpty {
                let length = settings.dayLimit ?? days.count
                summary += " \(skipped.count) didn't fit in \(length) day\(length == 1 ? "" : "s") and \(skipped.count == 1 ? "is" : "are") under Not Scheduled — add a day or raise the daily driving limit to fit \(skipped.count == 1 ? "it" : "them")."
            }
            if placed == 0 && skipped.isEmpty {
                summary += " No stops yet — find some with Along the Route, then build again."
            }
        }
        return Result(plan: plan, summary: summary)
    }

    // MARK: - Helpers

    private static func makeDay(index: Int, settings: TripSettings, start: TripPlanStart?) -> TripDayPlan {
        let date = Calendar.current.date(byAdding: .day, value: index, to: settings.startDate) ?? settings.startDate
        return TripDayPlan(
            date: date,
            start: start,
            startMinute: index == 0 ? settings.firstDayStartMinute : settings.dailyStartMinute,
            minutesPerStop: settings.minutesPerStop
        )
    }

    private static func place(on geometry: RouteGeometry, atMeters meters: Double, prefix: String) async -> TripPlanStart {
        let coordinate = geometry.coordinate(atMeters: meters)
        let town = await RouteFinderService.placeName(near: coordinate)
        return TripPlanStart(name: town.map { "\(prefix) \($0)" } ?? "\(prefix) mile \(Int(meters / RouteFinderService.metersPerMile))", latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// End the day near its last stop (that's where you'll be), named after its town.
    private static func overnightPlace(after stop: LocationEntryModel?, geometry: RouteGeometry, atMeters meters: Double) async -> TripPlanStart {
        guard let stop else { return await place(on: geometry, atMeters: meters, prefix: "Overnight near") }
        let coordinate = CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)
        let town = await RouteFinderService.placeName(near: coordinate)
        return TripPlanStart(name: "Overnight near \(town ?? (stop.title ?? "the last stop"))", latitude: stop.latitude, longitude: stop.longitude)
    }

    private static func timeZone(near coordinate: CLLocationCoordinate2D?) async -> TimeZone? {
        guard let coordinate else { return nil }
        return try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)).first?.timeZone
    }
}
