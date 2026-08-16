import Foundation

/// Sun azimuth/elevation from the standard NOAA solar position formulas (the same math
/// behind NOAA's public solar calculator), verified against known equinox/solstice
/// reference values before wiring in. Used to suggest when to come back for light that
/// matches the heading a spot was captured facing.
enum SunPositionEngine {
    struct Position {
        let azimuthDegrees: Double
        let elevationDegrees: Double
    }

    struct GoldenHourSuggestion {
        let time: Date
        let azimuthDegrees: Double
        let headingDeltaDegrees: Double
    }

    static func position(at date: Date, latitude: Double, longitude: Double) -> Position {
        let jd = julianDay(date)
        let t = (jd - 2451545.0) / 36525.0

        let l0 = normalizedDegrees(280.46646 + t * (36000.76983 + t * 0.0003032))
        let m = normalizedDegrees(357.52911 + t * (35999.05029 - 0.0001537 * t))
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)

        let mRad = m * .pi / 180
        let c = sin(mRad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * mRad) * (0.019993 - 0.000101 * t)
            + sin(3 * mRad) * 0.000289

        let trueLong = l0 + c
        let omega = 125.04 - 1934.136 * t
        let apparentLong = trueLong - 0.00569 - 0.00478 * sin(omega * .pi / 180)

        let meanObliquity = 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
        let obliquityCorrection = meanObliquity + 0.00256 * cos(omega * .pi / 180)

        let declinationRad = asin(sin(obliquityCorrection * .pi / 180) * sin(apparentLong * .pi / 180))

        let yFactor = pow(tan(obliquityCorrection * .pi / 360), 2)
        let eqTime = 4 * (yFactor * sin(2 * l0 * .pi / 180)
            - 2 * e * sin(mRad)
            + 4 * e * yFactor * sin(mRad) * cos(2 * l0 * .pi / 180)
            - 0.5 * yFactor * yFactor * sin(4 * l0 * .pi / 180)
            - 1.25 * e * e * sin(2 * mRad)) * 180 / .pi

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let components = utcCalendar.dateComponents([.hour, .minute, .second], from: date)
        let utcMinutes = Double(components.hour ?? 0) * 60 + Double(components.minute ?? 0) + Double(components.second ?? 0) / 60

        var trueSolarTime = (utcMinutes + eqTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        if trueSolarTime < 0 { trueSolarTime += 1440 }

        var hourAngle = trueSolarTime / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }

        let hourAngleRad = hourAngle * .pi / 180
        let latRad = latitude * .pi / 180

        let zenithRad = acos(sin(latRad) * sin(declinationRad) + cos(latRad) * cos(declinationRad) * cos(hourAngleRad))
        let elevation = 90 - zenithRad * 180 / .pi

        let azCalcRad = acos((sin(latRad) * cos(zenithRad) - sin(declinationRad)) / (cos(latRad) * sin(zenithRad)))
        let azCalc = azCalcRad * 180 / .pi
        let azimuth: Double
        if hourAngle > 0 {
            azimuth = (azCalc + 180).truncatingRemainder(dividingBy: 360)
        } else {
            azimuth = (540 - azCalc).truncatingRemainder(dividingBy: 360)
        }

        return Position(azimuthDegrees: azimuth, elevationDegrees: elevation)
    }

    /// Scans the given day for the moment (near sunrise or sunset, whichever is closer)
    /// when the sun's azimuth best matches `headingDegrees` while at golden-hour elevation.
    /// Returns nil only if the location/date has no golden-hour window at all (e.g. polar
    /// day/night) — a large headingDeltaDegrees just means an imperfect match, not a failure.
    static func goldenHourSuggestion(headingDegrees: Double, near date: Date, latitude: Double, longitude: Double) -> GoldenHourSuggestion? {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        guard let dayStart = utcCalendar.date(from: utcCalendar.dateComponents([.year, .month, .day], from: date)) else {
            return nil
        }

        var best: GoldenHourSuggestion?
        var minute = 0
        while minute < 24 * 60 {
            guard let sampleDate = utcCalendar.date(byAdding: .minute, value: minute, to: dayStart) else {
                minute += 2
                continue
            }
            let pos = position(at: sampleDate, latitude: latitude, longitude: longitude)
            if pos.elevationDegrees >= -1 && pos.elevationDegrees <= 8 {
                let delta = angularDifference(pos.azimuthDegrees, headingDegrees)
                if best == nil || delta < best!.headingDeltaDegrees {
                    best = GoldenHourSuggestion(time: sampleDate, azimuthDegrees: pos.azimuthDegrees, headingDeltaDegrees: delta)
                }
            }
            minute += 2
        }
        return best
    }

    private static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(diff, 360 - diff)
    }

    private static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    private static func normalizedDegrees(_ deg: Double) -> Double {
        let d = deg.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }
}
