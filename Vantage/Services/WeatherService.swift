import CoreLocation
import WeatherKit

/// Named WeatherLookup (not WeatherService) to avoid colliding with WeatherKit's own
/// WeatherKit.WeatherService type in this file's scope.
enum WeatherLookup {
    static func summary(for location: CLLocation) async -> String? {
        FileHandle.standardError.write("[VantageWeather] starting lookup for \(location.coordinate)\n".data(using: .utf8)!)
        do {
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location)
            let condition = weather.currentWeather.condition.description
            let temperature = weather.currentWeather.temperature.converted(to: .fahrenheit).value
            FileHandle.standardError.write("[VantageWeather] success: \(condition), \(temperature)F\n".data(using: .utf8)!)
            return "\(condition), \(Int(temperature.rounded()))°F"
        } catch {
            FileHandle.standardError.write("[VantageWeather] lookup failed: \(error)\n".data(using: .utf8)!)
            return nil
        }
    }
}
