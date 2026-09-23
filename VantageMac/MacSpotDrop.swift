import AppKit
import CoreLocation
import SwiftData
import UniformTypeIdentifiers

/// The Mac's answer to the iOS share extension: instead of a share sheet, you drag a
/// Street View screenshot (or any image) from Finder/Photos onto a spot to attach it,
/// or onto the map to start a new spot there — and drop or paste a Google Maps link to
/// turn it into a spot. Everything dragged/pasted funnels through `load(from:)`.
enum MacSpotDrop {
    enum Payload {
        case image(Data)
        case mapsLink(String)
    }

    /// File URLs first so a Finder drag reads the original file rather than the
    /// low-res preview some sources attach alongside it.
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .plainText]

    static func load(from providers: [NSItemProvider]) async -> Payload? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let fileURL = await loadFileURL(from: provider),
               let data = try? Data(contentsOf: fileURL),
               let jpeg = jpegData(from: data) {
                return .image(jpeg)
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let data = await loadData(from: provider, type: .image),
               let jpeg = jpegData(from: data) {
                return .image(jpeg)
            }
            for type in [UTType.url, .plainText] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                if let text = await loadText(from: provider, type: type), GoogleMapsLinkParser.looksLikeMapsLink(text) {
                    return .mapsLink(text)
                }
            }
        }
        return nil
    }

    /// Re-encodes as JPEG at the same quality the iOS camera path uses
    /// (`PhotoStorageService`), so a dropped 20 MB PNG screenshot doesn't land in
    /// CloudKit at full size. Returns nil for anything that isn't actually an image.
    static func jpegData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    // MARK: - Model changes

    static func attachPhoto(_ data: Data, to entry: LocationEntryModel, in context: ModelContext) {
        context.insert(PhotoAsset(imageData: data, isReference: true, entry: entry))
        try? context.save()
    }

    /// Same defaults as AddLocationView's planned spots (the "planned" tag, the active
    /// trip) so spots made by dropping/pasting look like any other desk-planned spot.
    @discardableResult
    static func createSpot(
        at coordinate: CLLocationCoordinate2D,
        title: String? = nil,
        photo: Data? = nil,
        in context: ModelContext
    ) -> LocationEntryModel {
        let entry = LocationEntryModel(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            title: title,
            tripID: ActiveTripStore.activeTripID
        )
        entry.tags.append("planned")
        context.insert(entry)
        if let photo {
            context.insert(PhotoAsset(imageData: photo, isReference: true, entry: entry))
        }
        try? context.save()
        return entry
    }

    @MainActor
    static func createSpot(fromMapsLink link: String, in context: ModelContext) async -> LocationEntryModel? {
        guard let place = await GoogleMapsLinkParser.resolvePlace(from: link) else { return nil }
        return createSpot(
            at: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            title: place.name,
            in: context
        )
    }

    // MARK: - NSItemProvider bridging

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }

    private static func loadData(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadText(from provider: NSItemProvider, type: UTType) async -> String? {
        if type == .url {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url?.absoluteString)
                }
            }
        }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }
}
