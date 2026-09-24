import Foundation

/// Hourly cloud cover for a place and time, from Open-Meteo's free forecast API — no
/// account or API key. (WeatherKit was removed from this app; see CLAUDE.md.)
///
/// Privacy: coordinates are rounded to 2 decimal places (~1 km) before being sent —
/// plenty for a weather forecast, and it never reveals a spot's exact location.
/// Licensing: free for non-commercial use with attribution ("Weather data by
/// Open-Meteo.com", shown in the planner and help). A paid tier of Photo Point would
/// need an Open-Meteo API subscription.
struct CloudForecast: Equatable {
    let time: Date
    /// Percent cover, total and by layer.
    let total: Int
    let low: Int
    let mid: Int
    let high: Int
    let precipitationChance: Int?

    /// A photographer's read on the numbers for golden-hour light.
    var summary: String {
        if let rain = precipitationChance, rain >= 50 { return "rain likely" }
        if low >= 70 { return "low cloud — sun likely blocked" }
        if total >= 90 { return "overcast" }
        if high >= 30, low < 40 { return "high cloud — could light up" }
        if total <= 20 { return "clear" }
        return "partly cloudy"
    }
}

enum CloudForecastService {
    /// Open-Meteo forecasts cover 16 days.
    static let maximumDaysAhead = 16

    private static var cache: [String: CloudForecast] = [:]

    @MainActor
    static func forecast(latitude: Double, longitude: Double, at date: Date) async -> CloudForecast? {
        guard date > Date().addingTimeInterval(-3600),
              date < Date().addingTimeInterval(Double(maximumDaysAhead) * 86_400) else { return nil }

        let lat = (latitude * 100).rounded() / 100
        let lng = (longitude * 100).rounded() / 100
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let hour = utc.dateInterval(of: .hour, for: date.addingTimeInterval(30 * 60))?.start ?? date
        let key = "\(lat),\(lng)@\(hour.timeIntervalSince1970)"
        if let cached = cache[key] { return cached }

        let day = hour.formatted(.iso8601.year().month().day())
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lng)),
            URLQueryItem(name: "hourly", value: "cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,precipitation_probability"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "start_date", value: day),
            URLQueryItem(name: "end_date", value: day)
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let hourly = decoded.hourly
        for index in hourly.time.indices {
            guard let time = formatter.date(from: hourly.time[index]) else { continue }
            let forecast = CloudForecast(
                time: time,
                total: hourly.cloud_cover[safe: index].flatMap { $0 } ?? 0,
                low: hourly.cloud_cover_low[safe: index].flatMap { $0 } ?? 0,
                mid: hourly.cloud_cover_mid[safe: index].flatMap { $0 } ?? 0,
                high: hourly.cloud_cover_high[safe: index].flatMap { $0 } ?? 0,
                precipitationChance: hourly.precipitation_probability?[safe: index].flatMap { $0 }
            )
            cache["\(lat),\(lng)@\(time.timeIntervalSince1970)"] = forecast
        }
        return cache[key]
    }

    // Field names match the API's JSON.
    private struct Response: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let cloud_cover: [Int?]
            let cloud_cover_low: [Int?]
            let cloud_cover_mid: [Int?]
            let cloud_cover_high: [Int?]
            let precipitation_probability: [Int?]?
        }
        let hourly: Hourly
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
