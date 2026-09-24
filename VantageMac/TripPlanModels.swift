import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UniformTypeIdentifiers

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

struct TripShotSheetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Saved plan (this Mac only)

/// A trip's day-by-day plan. Stored per trip in this Mac's UserDefaults as JSON, not
/// synced: syncing would need new CloudKit record types/fields deployed to the
/// Production schema first (see CLAUDE.md), which isn't worth it for planning state.
struct TripPlan: Codable, Equatable {
    var days: [TripDayPlan] = []

    private static func key(for tripID: UUID) -> String {
        "com.jamespennucci.Vantage.tripPlan.\(tripID.uuidString)"
    }

    /// The single-day planner's saved stop order, from before days existed.
    private static func legacyOrderKey(for tripID: UUID) -> String {
        "com.jamespennucci.Vantage.tripPlanOrder.\(tripID.uuidString)"
    }

    static func load(tripID: UUID) -> TripPlan? {
        guard let data = UserDefaults.standard.data(forKey: key(for: tripID)) else { return nil }
        return try? JSONDecoder().decode(TripPlan.self, from: data)
    }

    static func legacyOrder(tripID: UUID) -> [UUID] {
        (UserDefaults.standard.stringArray(forKey: legacyOrderKey(for: tripID)) ?? []).compactMap(UUID.init)
    }

    func save(tripID: UUID) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key(for: tripID))
        }
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
