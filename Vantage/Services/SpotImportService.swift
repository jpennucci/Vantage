import CoreLocation
import Foundation
import SwiftData

/// The JSON format for "researched elsewhere, import into Vantage" — deliberately
/// plain JSON rather than a Claude-specific format, so any AI assistant (or a human
/// typing it by hand) can produce a compatible file. Supports either raw coordinates
/// or a plain address (geocoded on import), since whoever's producing the file may
/// only have one or the other.
///
/// {
///   "name": "Optional collection name",
///   "spots": [
///     { "title": "Old barn off Route 9", "latitude": 40.7128, "longitude": -74.0060,
///       "tags": ["to shoot"], "note": "Good evening light" },
///     { "title": "Alt: address instead of coordinates", "address": "123 Main St, Anytown, NY" }
///   ]
/// }
struct ImportedSpot: Codable {
    var title: String?
    var latitude: Double?
    var longitude: Double?
    var address: String?
    var tags: [String]?
    var note: String?
}

struct SpotImportFile: Codable {
    var name: String?
    var spots: [ImportedSpot]
}

enum SpotImportService {
    /// A ready-to-paste prompt for any AI chat tool (Claude, ChatGPT, etc.) — spells
    /// out the exact JSON format above so the user doesn't have to remember or type
    /// the schema themselves. Ends with a blank line for them to describe what
    /// they're actually looking for.
    static let aiPromptTemplate = """
    I use an app called Vantage to track scouted photo/video locations. When I ask you to find locations, respond with ONLY a JSON object in exactly this format — no other text before or after it:

    {
      "name": "Short collection name",
      "spots": [
        {
          "title": "Short descriptive name",
          "latitude": 00.0000,
          "longitude": -00.0000,
          "tags": ["optional", "tags"],
          "note": "Optional short note"
        }
      ]
    }

    Notes:
    - Use "address": "full street address" instead of latitude/longitude if you don't have exact coordinates — either works, not both required.
    - Every spot needs coordinates or an address; nothing else is required.
    - Keep titles short and notes brief.

    Here's what I'm looking for:

    """

    static func parse(_ data: Data) -> [ImportedSpot]? {
        if let spots = try? JSONDecoder().decode(SpotImportFile.self, from: data).spots {
            return spots
        }
        guard let rawText = String(data: data, encoding: .utf8) else { return nil }

        // Typing/pasting through iOS's Smart Punctuation (or some AI replies) turns
        // straight quotes into curly ones, which isn't valid JSON — normalize before
        // trying again.
        let text = rawText
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")

        if let normalizedData = text.data(using: .utf8),
           let spots = try? JSONDecoder().decode(SpotImportFile.self, from: normalizedData).spots {
            return spots
        }

        // AI replies don't always follow "JSON only" — often wrapped in a markdown
        // code fence or a sentence of preamble/follow-up. Fall back to extracting
        // just the outermost {...} object from the text.
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              let extracted = String(text[start...end]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SpotImportFile.self, from: extracted).spots
    }

    /// Resolves address-only spots via geocoding; nil if a spot has neither
    /// coordinates nor a resolvable address.
    static func resolveCoordinates(for spot: ImportedSpot) async -> (latitude: Double, longitude: Double)? {
        if let lat = spot.latitude, let lng = spot.longitude {
            return (lat, lng)
        }
        guard let address = spot.address, !address.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let placemark = try? await CLGeocoder().geocodeAddressString(address).first,
              let location = placemark.location else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }

    /// Shared by both the file-import and paste-import paths, on both platforms —
    /// parses, resolves coordinates, inserts, and returns a human-readable summary.
    @MainActor
    static func importSpots(from data: Data, into modelContext: ModelContext) async -> String {
        guard let spots = parse(data) else {
            return "Couldn't find valid spot data there — check it matches the expected JSON format."
        }
        var importedCount = 0
        for spot in spots {
            guard let coordinate = await resolveCoordinates(for: spot) else { continue }
            let entry = LocationEntryModel(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                title: spot.title,
                note: spot.note,
                tags: (spot.tags ?? []) + ["imported"]
            )
            modelContext.insert(entry)
            importedCount += 1
        }
        try? modelContext.save()
        return "Imported \(importedCount) of \(spots.count) spot\(spots.count == 1 ? "" : "s")."
    }

    /// The "sharing" path for another Vantage user — not real-time CKShare (no
    /// participant invites, no live collaborative editing), just export-to-JSON /
    /// AirDrop-or-Messages-or-whatever / import-on-the-other-end, reusing the exact
    /// same schema and importSpots(from:into:) as the AI-research workflow above.
    static func exportJSON(_ entries: [LocationEntryModel], name: String) -> URL? {
        let spots = entries.map {
            ImportedSpot(title: $0.title, latitude: $0.latitude, longitude: $0.longitude, address: nil, tags: $0.tags, note: $0.note)
        }
        let file = SpotImportFile(name: name, spots: spots)
        guard let data = try? JSONEncoder().encode(file) else { return nil }
        let fileName = name.isEmpty ? "Vantage Spots" : name
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).json")
        do {
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            return nil
        }
    }
}
