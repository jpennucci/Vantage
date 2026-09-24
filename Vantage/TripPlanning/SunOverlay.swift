import CoreLocation
import MapKit
import SwiftUI

/// Sun position for the map's sun overlay at one moment, computed once for the map's
/// center. Across a region small enough to draw per-spot lines (a couple of degrees
/// at most) the sun's azimuth/elevation differ by well under a degree, so one
/// calculation serves every spot on screen and the time slider stays smooth.
struct SunOverlaySnapshot {
    let date: Date
    let position: SunPositionEngine.Position
    let day: TripPlanSunDay
    let sunriseAzimuth: Double?
    let sunsetAzimuth: Double?

    init(center: CLLocationCoordinate2D, day dayDate: Date, minuteOfDay: Double, timeZone: TimeZone) {
        let day = TripPlanSunDay(latitude: center.latitude, longitude: center.longitude, day: dayDate, timeZone: timeZone, headingDegrees: nil)
        self.day = day
        date = SunOverlaySnapshot.dayStart(dayDate, in: timeZone).addingTimeInterval(minuteOfDay * 60)
        position = SunPositionEngine.position(at: date, latitude: center.latitude, longitude: center.longitude)
        sunriseAzimuth = day.sunrise.map { SunPositionEngine.position(at: $0, latitude: center.latitude, longitude: center.longitude).azimuthDegrees }
        sunsetAzimuth = day.sunset.map { SunPositionEngine.position(at: $0, latitude: center.latitude, longitude: center.longitude).azimuthDegrees }
    }

    /// Midnight at the start of the picked calendar date, in the map area's time zone.
    static func dayStart(_ day: Date, in timeZone: TimeZone) -> Date {
        TripPlanning.dayStart(day, in: timeZone)
    }

    func minuteOfDay(for date: Date?, timeZone: TimeZone, day: Date) -> Double? {
        guard let date else { return nil }
        return date.timeIntervalSince(SunOverlaySnapshot.dayStart(day, in: timeZone)) / 60
    }
}

enum SunGeometry {
    /// Point `meters` away from `origin` along compass `bearing` — flat-earth math,
    /// plenty accurate for the few-kilometer lines drawn on the map.
    static func destination(from origin: CLLocationCoordinate2D, bearing: Double, meters: Double) -> CLLocationCoordinate2D {
        let radians = bearing * .pi / 180
        let metersPerDegreeLatitude = 111_320.0
        let dLat = meters * cos(radians) / metersPerDegreeLatitude
        let dLng = meters * sin(radians) / (metersPerDegreeLatitude * cos(origin.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: origin.latitude + dLat, longitude: origin.longitude + dLng)
    }
}

/// The date + time-of-day controls at the bottom of the map while the sun overlay is on.
struct SunOverlayPanel: View {
    @Binding var day: Date
    @Binding var minuteOfDay: Double
    let snapshot: SunOverlaySnapshot
    let timeZone: TimeZone
    let showsLines: Bool

    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    private func jump(to date: Date?) {
        if let minute = snapshot.minuteOfDay(for: date, timeZone: timeZone, day: day) {
            withAnimation { minuteOfDay = min(max(minute, 0), 1439) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                DatePicker("Date", selection: $day, displayedComponents: .date)
                    .labelsHidden()
                    .fixedSize()
                Text(time(snapshot.date))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppTheme.apertureGold)
                if snapshot.position.elevationDegrees > -0.833 {
                    Text(String(format: "Sun %.0f° high · %.0f°", snapshot.position.elevationDegrees, snapshot.position.azimuthDegrees))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sun below the horizon")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if timeZone != .current {
                    Text(timeZone.localizedName(for: .shortStandard, locale: .current) ?? timeZone.identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Times are in the time zone of the area shown on the map")
                }
            }

            ZStack(alignment: .leading) {
                SunDayTrack(snapshot: snapshot, timeZone: timeZone, day: day)
                    .frame(height: 6)
                    .padding(.horizontal, 10)
                    .offset(y: -1)
                Slider(value: $minuteOfDay, in: 0...1439)
            }

            HStack(spacing: 8) {
                Button("Sunrise \(time(snapshot.day.sunrise))") { jump(to: snapshot.day.sunrise) }
                Button("Morning Gold") { jump(to: midpoint(snapshot.day.sunrise, snapshot.day.morningGoldenEnd)) }
                Button("Noon") { withAnimation { minuteOfDay = 12 * 60 } }
                Button("Evening Gold") { jump(to: midpoint(snapshot.day.eveningGoldenStart, snapshot.day.sunset)) }
                Button("Sunset \(time(snapshot.day.sunset))") { jump(to: snapshot.day.sunset) }
                Spacer()
                if !showsLines {
                    Text("Zoom in to see sun lines at each spot")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(12)
        .frame(maxWidth: 760)
    }

    private func midpoint(_ a: Date?, _ b: Date?) -> Date? {
        guard let a, let b else { return nil }
        return a.addingTimeInterval(b.timeIntervalSince(a) / 2)
    }
}

/// Night / golden hour / daylight bands behind the time slider, so you can see at a
/// glance where the good light falls in the day.
private struct SunDayTrack: View {
    let snapshot: SunOverlaySnapshot
    let timeZone: TimeZone
    let day: Date

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x: (Date?) -> CGFloat? = { date in
                snapshot.minuteOfDay(for: date, timeZone: timeZone, day: day).map { CGFloat($0 / 1440) * width }
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.55))
                if let rise = x(snapshot.day.sunrise), let set = x(snapshot.day.sunset) {
                    Rectangle().fill(Color.white.opacity(0.28))
                        .frame(width: max(set - rise, 0))
                        .offset(x: rise)
                }
                if let start = x(snapshot.day.sunrise), let end = x(snapshot.day.morningGoldenEnd) {
                    Rectangle().fill(AppTheme.apertureGold)
                        .frame(width: max(end - start, 0))
                        .offset(x: start)
                }
                if let start = x(snapshot.day.eveningGoldenStart), let end = x(snapshot.day.sunset) {
                    Rectangle().fill(AppTheme.apertureGold)
                        .frame(width: max(end - start, 0))
                        .offset(x: start)
                }
            }
            .clipShape(Capsule())
        }
        .allowsHitTesting(false)
    }
}
