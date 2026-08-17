import Foundation

/// Extracts coordinates from a pasted Google Maps link, for the "route planning at
/// home" workflow — paste a link found while researching in a browser, get an entry.
/// Pure URL parsing plus a plain HTTP redirect follow for shortened links; no API key
/// or billing, unlike the Google Maps JavaScript/Places APIs.
enum GoogleMapsLinkParser {
    static func resolveCoordinates(from rawText: String) async -> (latitude: Double, longitude: Double)? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: trimmed) else { return nil }

        // Shortened links (maps.app.goo.gl, goo.gl) don't carry coordinates in the URL
        // itself — resolve the redirect first to get the real, long-form URL.
        if let host = url.host, host.contains("goo.gl") {
            if let resolved = await resolveRedirect(url) {
                url = resolved
            }
        }

        let urlString = url.absoluteString

        // Most common share-link format: .../@lat,lng,zoom
        if let match = firstMatch(in: urlString, pattern: #"@(-?\d+\.\d+),(-?\d+\.\d+)"#) {
            return match
        }
        // ?q=lat,lng or ?query=lat,lng
        if let match = firstMatch(in: urlString, pattern: #"[?&](?:q|query)=(-?\d+\.\d+),(-?\d+\.\d+)"#) {
            return match
        }
        // ?ll=lat,lng
        if let match = firstMatch(in: urlString, pattern: #"[?&]ll=(-?\d+\.\d+),(-?\d+\.\d+)"#) {
            return match
        }
        // Embedded place data format: !3d<lat>!4d<lng>
        if let match = firstMatch(in: urlString, pattern: #"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)"#) {
            return match
        }
        return nil
    }

    private static func resolveRedirect(_ url: URL) async -> URL? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response.url
        } catch {
            return nil
        }
    }

    private static func firstMatch(in string: String, pattern: String) -> (latitude: Double, longitude: Double)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              match.numberOfRanges >= 3,
              let latRange = Range(match.range(at: 1), in: string),
              let lngRange = Range(match.range(at: 2), in: string),
              let latitude = Double(string[latRange]),
              let longitude = Double(string[lngRange]) else { return nil }
        return (latitude, longitude)
    }
}
