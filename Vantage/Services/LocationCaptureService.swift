import CoreLocation
import Foundation

/// Core one-tap capture: grabs GPS + heading and produces a `LocationEntryModel`.
/// This is the essential MVP loop — no photo/note/weather/sync wiring yet.
@MainActor
final class LocationCaptureService: NSObject, ObservableObject {
    @Published var lastError: String?
    @Published var isCapturing = false

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 1
    }

    func requestPermissionIfNeeded() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Captures the current GPS location and compass heading and returns a new entry.
    /// `isCapturing` isn't toggled here — CaptureAndSaveUseCase owns that so a button
    /// stays disabled through weather/tag fetching too, not just the GPS fix.
    func captureLocation() async -> LocationEntryModel? {
        do {
            let location = try await currentLocation()
            // GPS course-over-ground reflects the direction of travel, which is what
            // matters while driving — the phone's magnetometer heading instead reports
            // which way the device's top edge points, which a car's dashboard metal and
            // mount orientation can easily throw off by up to 180°. Compass heading is
            // only used as a fallback for when you're stationary and course is invalid
            // (CLLocation reports course as negative in that case).
            let validHeading: Double?
            if location.course >= 0 {
                validHeading = location.course
            } else {
                let heading = manager.heading?.trueHeading
                validHeading = (heading ?? -1) >= 0 ? heading : nil
            }

            return LocationEntryModel(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                headingDegrees: validHeading
            )
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// One-shot GPS fix without creating an entry — used for "near me" sorting, which
    /// shouldn't touch `isCapturing` since it isn't a capture.
    func currentCoordinate() async -> CLLocation? {
        try? await currentLocation()
    }

    private func currentLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            manager.startUpdatingHeading()
            manager.requestLocation()
        }
    }
}

extension LocationCaptureService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            manager.stopUpdatingHeading()
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            manager.stopUpdatingHeading()
            self.locationContinuation?.resume(throwing: error)
            self.locationContinuation = nil
        }
    }
}
