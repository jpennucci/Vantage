import CoreLocation
import Foundation

/// Town names for spots ("Montauk, NY") for list rows, looked up once per area and
/// remembered across launches. Not stored on the spot itself: that would mean a
/// CloudKit schema change for what is only a label, and the cache rebuilds itself
/// from the coordinates on any device.
@MainActor
final class PlaceNameService {
    static let shared = PlaceNameService()

    private static let defaultsKey = "placeNamesByArea"
    private var names: [String: String]
    /// Areas with no usable placemark (open ocean, a failed lookup) — not persisted,
    /// so a lookup that failed offline gets another try next launch.
    private var misses: Set<String> = []
    private var inFlight: [String: Task<String?, Never>] = [:]
    /// Apple throttles reverse geocoding (roughly one request a second is safe), so a
    /// long list waits its turn instead of failing in a burst.
    private var nextSlot = Date.distantPast

    private init() {
        names = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    /// ~1 km cells, so neighboring spots share one lookup.
    private static func area(_ latitude: Double, _ longitude: Double) -> String {
        String(format: "%.2f,%.2f", latitude, longitude)
    }

    /// Already known — no lookup. For a row's first render, so it doesn't flicker.
    func cachedName(latitude: Double, longitude: Double) -> String? {
        names[Self.area(latitude, longitude)]
    }

    func name(latitude: Double, longitude: Double) async -> String? {
        let area = Self.area(latitude, longitude)
        if let name = names[area] { return name }
        if misses.contains(area) { return nil }
        if let task = inFlight[area] { return await task.value }

        let slot = max(Date(), nextSlot)
        nextSlot = slot.addingTimeInterval(1.1)
        let task = Task<String?, Never> {
            let wait = slot.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            let location = CLLocation(latitude: latitude, longitude: longitude)
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
            return Self.label(for: placemark)
        }
        inFlight[area] = task
        let name = await task.value
        inFlight[area] = nil
        if let name {
            names[area] = name
            UserDefaults.standard.set(names, forKey: Self.defaultsKey)
        } else {
            misses.insert(area)
        }
        return name
    }

    /// "Montauk, NY": the town and its state or region, whichever parts exist.
    private nonisolated static func label(for placemark: CLPlacemark) -> String? {
        let town = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.name
        let parts = [town, placemark.administrativeArea].compactMap { $0 }
        let unique = parts.enumerated().filter { index, part in !parts[..<index].contains(part) }.map(\.element)
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }
}
