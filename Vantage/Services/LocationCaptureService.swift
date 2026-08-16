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
    func captureLocation() async -> LocationEntryModel? {
        isCapturing = true
        defer { isCapturing = false }

        do {
            let location = try await currentLocation()
            let heading = manager.heading?.trueHeading
            let validHeading = (heading ?? -1) >= 0 ? heading : nil

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
