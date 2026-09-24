import CoreLocation
import Foundation
import SwiftData

/// The JSON format for "researched elsewhere, import into Photo Point" — deliberately
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
    /// Where the AI found it (a forum thread, blog, local history site) — kept in the
    /// spot's note so you can check it before driving out of your way.
    var source: String?
    /// Link to that page, kept in the note (spot details show it as a tappable link).
    var sourceURL: String?
    /// A direct link to a photo of the place; see SpotPictureService.
    var imageURL: String?

    enum CodingKeys: String, CodingKey {
        case title, latitude, longitude, address, tags, note, source
        case sourceURL = "source_url"
        case imageURL = "image_url"
    }
}

struct SpotImportFile: Codable {
    var name: String?
    var spots: [ImportedSpot]
}

/// Where an existing trip is, in words an AI chat tool can use to keep suggestions
/// nearby — town names looked up from the trip's own spots, plus their bounding box
/// and names so the AI doesn't suggest what's already there.
struct TripArea {
    var placeNames: [String]
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double
    var existingTitles: [String]
}

enum SpotImportService {
    /// A ready-to-paste prompt for any AI chat tool (Claude, ChatGPT, etc.) — spells
    /// out the exact JSON format above so the user doesn't have to remember or type
    /// the schema themselves. Ends with a blank line for them to describe what
    /// they're actually looking for.
    static let aiPromptTemplate = """
    I use an app called Photo Point to track scouted photo/video locations. When I ask you to find locations, respond with ONLY a JSON object in exactly this format — no other text before or after it:

    {
      "name": "Short collection name",
      "spots": [
        {
          "title": "Short descriptive name",
          "latitude": 00.0000,
          "longitude": -00.0000,
          "tags": ["optional", "tags"],
          "note": "Optional short note",
          "source_url": "Optional link to where you found it",
          "image_url": "Optional direct link to a photo of the place (.jpg or .png)"
        }
      ]
    }

    Notes:
    - Use "address": "full street address" instead of latitude/longitude if you don't have exact coordinates — either works, not both required.
    - Every spot needs coordinates or an address; nothing else is required.
    - Keep titles short and notes brief.

    Here's what I'm looking for:

    """

    static func parse(_ data: Data) -> SpotImportFile? {
        if let file = try? JSONDecoder().decode(SpotImportFile.self, from: data) {
            return file
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
           let file = try? JSONDecoder().decode(SpotImportFile.self, from: normalizedData) {
            return file
        }

        // AI replies don't always follow "JSON only" — often wrapped in a markdown
        // code fence or a sentence of preamble/follow-up. Fall back to extracting
        // just the outermost {...} object from the text.
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              let extracted = String(text[start...end]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SpotImportFile.self, from: extracted)
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

    /// The standard prompt, narrowed to an existing trip's area when given one.
    static func aiPrompt(near area: TripArea?) -> String {
        guard let area else { return aiPromptTemplate }
        var constraint = "Only suggest places in or near the area where I already have spots"
        if !area.placeNames.isEmpty {
            constraint += " — around \(area.placeNames.joined(separator: "; "))"
        }
        constraint += String(
            format: " (roughly latitude %.3f to %.3f, longitude %.3f to %.3f; a short drive outside that is fine).",
            area.minLatitude, area.maxLatitude, area.minLongitude, area.maxLongitude
        )
        if !area.existingTitles.isEmpty {
            constraint += " I already have these, so don't repeat them: \(area.existingTitles.prefix(25).joined(separator: ", "))."
        }
        return aiPromptTemplate.replacingOccurrences(
            of: "Here's what I'm looking for:",
            with: "\(constraint)\n\nHere's what I'm looking for:"
        )
    }

    /// Up to four town names spread across the trip (reverse geocoding is rate
    /// limited, and a handful is plenty to describe an area to an AI).
    static func area(of entries: [LocationEntryModel]) async -> TripArea? {
        guard !entries.isEmpty else { return nil }
        let latitudes = entries.map(\.latitude), longitudes = entries.map(\.longitude)
        let samples = [
            entries.min { $0.latitude < $1.latitude }, entries.max { $0.latitude < $1.latitude },
            entries.min { $0.longitude < $1.longitude }, entries.max { $0.longitude < $1.longitude }
        ].compactMap { $0 }
        var placeNames: [String] = []
        for entry in samples {
            let location = CLLocation(latitude: entry.latitude, longitude: entry.longitude)
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { continue }
            let name = [placemark.locality ?? placemark.subAdministrativeArea, placemark.administrativeArea]
                .compactMap { $0 }
                .joined(separator: ", ")
            if !name.isEmpty, !placeNames.contains(name) {
                placeNames.append(name)
            }
        }
        return TripArea(
            placeNames: placeNames,
            minLatitude: latitudes.min()!, maxLatitude: latitudes.max()!,
            minLongitude: longitudes.min()!, maxLongitude: longitudes.max()!,
            existingTitles: entries.compactMap { $0.title?.isEmpty == false ? $0.title : nil }
        )
    }

    /// Shared by both the file-import and paste-import paths, on both platforms —
    /// parses, resolves coordinates, inserts, and returns a human-readable summary.
    /// Every successfully imported spot in a batch lands in the same new trip, named
    /// from the AI response's own collection name when it provided one, falling back
    /// to a timestamp — either way a placeholder the user can rename afterward. This
    /// keeps a batch of a dozen+ imported spots easy to find and filter together
    /// instead of scattering into the general list.
    @MainActor
    static func importSpots(
        from data: Data,
        into modelContext: ModelContext,
        addingTo existingTrip: TripModel? = nil,
        extraTags: [String] = [],
        verifyAddresses: Bool = false
    ) async -> String {
        await importSpotsWithDetails(from: data, into: modelContext, addingTo: existingTrip, extraTags: extraTags, verifyAddresses: verifyAddresses).summary
    }

    struct ImportResult {
        let summary: String
        /// Each new spot with the image link the AI gave for it, if any — for
        /// SpotPictureService to fill in pictures after the import returns.
        let imported: [(entry: LocationEntryModel, imageURL: String?)]
    }

    @MainActor
    static func importSpotsWithDetails(
        from data: Data,
        into modelContext: ModelContext,
        addingTo existingTrip: TripModel? = nil,
        extraTags: [String] = [],
        verifyAddresses: Bool = false
    ) async -> ImportResult {
        guard let file = parse(data) else {
            return ImportResult(summary: "Couldn't find valid spot data there — check it matches the expected JSON format.", imported: [])
        }
        var imageLinks: [UUID: String] = [:]
        let spots = file.spots
        var importedEntries: [LocationEntryModel] = []
        var unverifiedCount = 0
        for spot in spots {
            guard let coordinate = await resolveCoordinates(for: spot) else { continue }
            var tags = (spot.tags ?? []) + ["imported"] + extraTags
            if verifyAddresses, await !addressMatches(spot, coordinate) {
                tags.append(unverifiedTag)
                unverifiedCount += 1
            }
            let sourceLine: String? = {
                switch (spot.source?.trimmingCharacters(in: .whitespaces), spot.sourceURL?.trimmingCharacters(in: .whitespaces)) {
                case let (name?, url?) where !name.isEmpty && !url.isEmpty: return "Source: \(name) — \(url)"
                case let (name?, _) where !name.isEmpty: return "Source: \(name)"
                case let (_, url?) where !url.isEmpty: return "Source: \(url)"
                default: return nil
                }
            }()
            let note = [spot.note, sourceLine]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            let entry = LocationEntryModel(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                title: spot.title,
                note: note.isEmpty ? nil : note,
                tags: tags
            )
            modelContext.insert(entry)
            importedEntries.append(entry)
            if let link = spot.imageURL?.trimmingCharacters(in: .whitespaces), !link.isEmpty {
                imageLinks[entry.id] = link
            }
        }

        if let existingTrip {
            // "Find more near this trip" — keep the new finds with the trip they're for.
            for entry in importedEntries {
                entry.tripID = existingTrip.id
            }
        } else if !importedEntries.isEmpty {
            let trimmedName = file.name?.trimmingCharacters(in: .whitespaces) ?? ""
            let tripName = trimmedName.isEmpty ? "Import \(Date().formatted(date: .abbreviated, time: .shortened))" : trimmedName
            let trip = TripModel(name: tripName)
            modelContext.insert(trip)
            for entry in importedEntries {
                entry.tripID = trip.id
            }
        }

        try? modelContext.save()
        let destination = existingTrip.map { " into \($0.name)" } ?? ""
        let unverified = unverifiedCount > 0 ? " \(unverifiedCount) couldn't be verified (address and coordinates disagree) and are tagged “\(unverifiedTag)”." : ""
        return ImportResult(
            summary: "Imported \(importedEntries.count) of \(spots.count) spot\(spots.count == 1 ? "" : "s")\(destination).\(unverified)",
            imported: importedEntries.map { (entry: $0, imageURL: imageLinks[$0.id]) }
        )
    }

    static let unverifiedTag = "unverified"

    /// AI tools sometimes invent places or misplace real ones. When a spot comes with
    /// both an address and coordinates, geocode the address and check they agree
    /// (within 3 km — addresses in the countryside geocode loosely). With nothing to
    /// cross-check, the spot is given the benefit of the doubt.
    private static func addressMatches(_ spot: ImportedSpot, _ coordinate: (latitude: Double, longitude: Double)) async -> Bool {
        guard spot.latitude != nil, let address = spot.address, !address.isEmpty,
              let placemark = try? await CLGeocoder().geocodeAddressString(address).first,
              let location = placemark.location else { return true }
        let given = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location.distance(from: given) < 3000
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
        let fileName = name.isEmpty ? "Photo Point Spots" : name
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).json")
        do {
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            return nil
        }
    }
}
