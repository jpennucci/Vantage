import CoreLocation
import WeatherKit

/// Named WeatherLookup (not WeatherService) to avoid colliding with WeatherKit's own
/// WeatherKit.WeatherService type in this file's scope.
enum WeatherLookup {
    static func summary(for location: CLLocation) async -> String? {
        do {
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location)
            let condition = weather.currentWeather.condition.description
            let temperature = weather.currentWeather.temperature.converted(to: .fahrenheit).value
            return "\(condition), \(Int(temperature.rounded()))°F"
        } catch {
            return nil
        }
    }
}
