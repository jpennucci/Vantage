import Foundation

/// Exports entries as KML for the "send anyone a map link" sharing path — import into
/// Google My Maps and anyone gets a shareable map, no second Vantage user or account
/// needed on their end. Pure Foundation, no network/API key required.
enum KMLExportService {
    static func export(_ entries: [LocationEntryModel], name: String) -> URL? {
        var placemarks = ""
        for entry in entries {
            let title = escapeXML(entry.title?.isEmpty == false ? entry.title! : "Untitled Spot")

            var descriptionParts: [String] = []
            if !entry.tags.isEmpty { descriptionParts.append("Tags: \(entry.tags.joined(separator: ", "))") }
            if let note = entry.note, !note.isEmpty { descriptionParts.append("Note: \(note)") }
            if let parking = entry.parkingNotes, !parking.isEmpty { descriptionParts.append("Parking: \(parking)") }
            if !entry.shotList.isEmpty {
                let shots = entry.shotList.map { "\($0.isDone ? "[x]" : "[ ]") \($0.text)" }.joined(separator: ", ")
                descriptionParts.append("Shot List: \(shots)")
            }
            descriptionParts.append("Captured: \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
            let description = escapeXML(descriptionParts.joined(separator: "\n"))

            placemarks += """
            <Placemark>
              <name>\(title)</name>
              <description>\(description)</description>
              <Point>
                <coordinates>\(entry.longitude),\(entry.latitude),0</coordinates>
              </Point>
            </Placemark>

            """
        }

        let kml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>\(escapeXML(name))</name>
            \(placemarks)
          </Document>
        </kml>
        """

        let fileName = name.isEmpty ? "Vantage Export" : name
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).kml")
        do {
            try kml.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
