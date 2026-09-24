import CoreLocation

/// One-shot "where am I right now" for trip planning — a day's start point or a
/// route's start — on both iPhone and Mac. Named after the nearest town.
enum CurrentLocation {
    /// nil if location access is denied or no fix arrives within `timeout` seconds.
    @MainActor
    static func place(timeout: TimeInterval = 15) async -> TripPlanStart? {
        let manager = CLLocationManager()
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        let location: CLLocation? = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 1000 {
                            return location
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        withExtendedLifetime(manager) {}
        guard let location else { return nil }
        let town = await RouteFinderService.placeName(near: location.coordinate)
        return TripPlanStart(
            name: town.map { "Current location (\($0))" } ?? "Current location",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }
}
