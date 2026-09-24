import CoreLocation
import Foundation
import MapKit
import SwiftUI

struct TripPlanLeg {
    let travelTime: TimeInterval
    let distance: CLLocationDistance
    let polyline: MKPolyline

    /// Keyed by the two endpoints' coordinates (not spot IDs) so a leg from a day's
    /// starting point — which isn't a spot — caches the same way, and a leg is reused
    /// wherever the same pair of places appears.
    static func key(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f>%.5f,%.5f", from.latitude, from.longitude, to.latitude, to.longitude)
    }
}

/// Sun events for one spot on one local calendar day. Scans that day minute by minute
/// with `SunPositionEngine.position`, the same NOAA math the rest of the app uses.
/// Unlike `goldenHourSuggestion` (which scans a UTC day), this scans the *local* day,
/// so a West Coast sunset doesn't slip into the next UTC date.
struct TripPlanSunDay {
    var sunrise: Date?
    var sunset: Date?
    /// Morning golden hour runs sunrise → sun at 6°; evening runs 6° → sunset.
    var morningGoldenEnd: Date?
    var eveningGoldenStart: Date?
    /// Moment the sun's azimuth best matches the spot's capture heading at golden-hour
    /// elevation — nil for spots without a heading (e.g. ones added from a link).
    var bestLight: Date?

    init(latitude: Double, longitude: Double, day: Date, timeZone: TimeZone, headingDegrees: Double?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Take the y/m/d the user picked (in the Mac's calendar) and start that same
        // calendar date at midnight in the trip's time zone.
        let picked = Calendar.current.dateComponents([.year, .month, .day], from: day)
        guard let dayStart = calendar.date(from: picked) else { return }

        let horizon = -0.833 // standard refraction-corrected sunrise/sunset altitude
        let golden = 6.0
        var previous: Double?
        var bestDelta = Double.infinity

        for minute in 0...(24 * 60) {
            let sample = dayStart.addingTimeInterval(Double(minute) * 60)
            let position = SunPositionEngine.position(at: sample, latitude: latitude, longitude: longitude)
            let elevation = position.elevationDegrees
            if let previous {
                if previous < horizon, elevation >= horizon, sunrise == nil { sunrise = sample }
                if previous < golden, elevation >= golden, morningGoldenEnd == nil { morningGoldenEnd = sample }
                if previous >= golden, elevation < golden { eveningGoldenStart = sample }
                if previous >= horizon, elevation < horizon { sunset = sample }
            }
            previous = elevation

            if let headingDegrees, elevation >= -1, elevation <= 8 {
                let diff = abs(position.azimuthDegrees - headingDegrees).truncatingRemainder(dividingBy: 360)
                let delta = min(diff, 360 - diff)
                if delta < bestDelta {
                    bestDelta = delta
                    bestLight = sample
                }
            }
        }
    }
}

// MARK: - Trip plan (synced on the trip)

/// A trip's day-by-day plan, stored JSON-encoded in `TripModel.planData` so it syncs
/// with the trip (Mac planning, iPhone on the road). Before 2026-09-24 plans lived in
/// the Mac's UserDefaults; `TripModel.plan` migrates one on first read.
struct TripPlan: Codable, Equatable {
    var days: [TripDayPlan] = []

    /// Pre-sync Mac-only storage, read once for migration.
    fileprivate static func legacyMacPlan(tripID: UUID) -> TripPlan? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "com.jamespennucci.Vantage.tripPlan.\(tripID.uuidString)"),
           let plan = try? JSONDecoder().decode(TripPlan.self, from: data), !plan.days.isEmpty {
            return plan
        }
        // The single-day planner's stop order, from before days existed.
        let order = (defaults.stringArray(forKey: "com.jamespennucci.Vantage.tripPlanOrder.\(tripID.uuidString)") ?? []).compactMap(UUID.init)
        return order.isEmpty ? nil : TripPlan(days: [TripDayPlan(date: Date(), stopIDs: order)])
    }
}

extension TripModel {
    /// nil until the trip has been planned (on any device).
    var plan: TripPlan? {
        get {
            if let planData, let plan = try? JSONDecoder().decode(TripPlan.self, from: planData) {
                return plan
            }
            return TripPlan.legacyMacPlan(tripID: id)
        }
        set {
            planData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var route: TripRoute {
        get { routeData.flatMap { try? JSONDecoder().decode(TripRoute.self, from: $0) } ?? TripRoute() }
        set { routeData = try? JSONEncoder().encode(newValue) }
    }
}

enum TripPlanning {
    /// Midnight at the start of `day`'s calendar date (as picked in the device's
    /// calendar), interpreted in the trip's time zone.
    static func dayStart(_ day: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let picked = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return calendar.date(from: picked) ?? day
    }
}

struct TripDayPlan: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Only the calendar date matters (read in the Mac's calendar, then interpreted in
    /// the trip's time zone — same as TripPlanSunDay).
    var date: Date
    var stopIDs: [UUID] = []
    /// Where the day's driving begins (hotel, campsite…); nil = start at the first stop.
    var start: TripPlanStart?
    /// Minutes after local midnight (trip time zone) when you leave the start — or
    /// arrive at the first stop when there's no start point.
    var startMinute: Double = 6 * 60
    var minutesPerStop: Double = 30
}

struct TripPlanStart: Codable, Equatable {
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// One stop's place in a day's schedule.
struct TripScheduleItem: Identifiable {
    var id: UUID { entry.id }
    let entry: LocationEntryModel
    let legFromPrevious: TripPlanLeg?
    let arrival: Date
    let departure: Date
    let sun: TripPlanSunDay

    enum Status {
        case onTime
        case early(TimeInterval)
        case late(TimeInterval)
        case afterSunset
        case unknown
    }

    /// The light you're aiming for: the heading-matched best light, or — for spots
    /// without a heading — the middle of whichever golden hour (morning/evening) is
    /// nearer the arrival time.
    var target: Date? {
        if let best = sun.bestLight { return best }
        let morning = TripScheduleItem.midpoint(sun.sunrise, sun.morningGoldenEnd)
        let evening = TripScheduleItem.midpoint(sun.eveningGoldenStart, sun.sunset)
        guard let morning, let evening else { return morning ?? evening }
        return abs(arrival.timeIntervalSince(morning)) < abs(arrival.timeIntervalSince(evening)) ? morning : evening
    }

    var status: Status {
        if let sunset = sun.sunset, arrival > sunset.addingTimeInterval(20 * 60) {
            return .afterSunset
        }
        guard let target else { return .unknown }
        let difference = arrival.timeIntervalSince(target)
        if difference > 10 * 60 { return .late(difference) }
        if difference < -60 * 60 { return .early(-difference) }
        return .onTime
    }

    static func midpoint(_ a: Date?, _ b: Date?) -> Date? {
        guard let a, let b else { return nil }
        return a.addingTimeInterval(b.timeIntervalSince(a) / 2)
    }
}

// MARK: - Route finder

/// The "Find Along the Route" setup for a trip, stored in `TripModel.routeData`.
struct TripRoute: Codable, Equatable {
    var start: TripPlanStart?
    var end: TripPlanStart?
    /// Towns/places to route through, in order — e.g. the towns along historic Route 66,
    /// which a fastest-route calculation would otherwise skip in favor of I-40.
    var waypoints: [TripPlanStart] = []
    /// Free-text routing guidance passed to the AI, e.g. "Stay on historic Route 66".
    var guidance: String = ""
    var interests: [String] = []
    var customInterests: String = ""
    var maxDetourMiles: Double = 15
    var segmentMiles: Double = 275
    /// Segment numbers (1-based) whose AI results have been pasted in.
    var completedSegments: [Int] = []

    var hasEnds: Bool { start != nil && end != nil }

    /// Quick picks — the kinds of things that take hours of forum/blog digging to find,
    /// not what a map search for "gas station" already does well.
    static let suggestedInterests = [
        "Roadside oddities", "Abandoned places", "Ghost towns", "Vintage neon signs",
        "Murals & folk art", "Classic diners", "Historic gas stations & motels",
        "Scenic overlooks", "Historical markers", "Quirky museums", "Photogenic bridges",
        "Local legends & film locations"
    ]

    var allInterests: [String] {
        let custom = customInterests
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return interests + custom
    }
}
