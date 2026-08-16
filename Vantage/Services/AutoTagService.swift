import CoreLocation
import CoreMotion

enum AutoTagService {
    /// Synchronous — pure math off the existing sun-position engine, no I/O — so it can
    /// be applied immediately at capture time rather than backfilled later.
    static func timeOfDayTag(at date: Date, latitude: Double, longitude: Double) -> String {
        let elevation = SunPositionEngine.position(at: date, latitude: latitude, longitude: longitude).elevationDegrees
        switch elevation {
        case ..<(-6.0):
            return "Night"
        case -6.0..<(-1.0):
            return "Blue Hour"
        case -1.0..<8.0:
            return "Golden Hour"
        default:
            return "Midday"
        }
    }

    static func regionTag(for location: CLLocation) async -> String? {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            return placemarks.first?.administrativeArea ?? placemarks.first?.locality
        } catch {
            return nil
        }
    }

    private static let motionManager = CMMotionActivityManager()

    static func motionTag() async -> String? {
        guard CMMotionActivityManager.isActivityAvailable() else { return nil }
        let now = Date()
        return await withCheckedContinuation { continuation in
            motionManager.queryActivityStarting(from: now.addingTimeInterval(-30), to: now, to: .main) { activities, _ in
                guard let activity = activities?.last else {
                    continuation.resume(returning: nil)
                    return
                }
                if activity.automotive {
                    continuation.resume(returning: "Driving")
                } else if activity.walking || activity.running || activity.cycling {
                    continuation.resume(returning: "On Foot")
                } else if activity.stationary {
                    continuation.resume(returning: "Stationary")
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
