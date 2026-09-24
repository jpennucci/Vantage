import CoreGraphics
import ImageIO
import MapKit
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Gives an AI-imported spot a picture, so a list of finds is something you can scan
/// rather than a wall of names. Tries, in order:
///
/// 1. **The image link the AI supplied** — kept only if it actually downloads as an
///    image (AI chats often invent image URLs; web-search-enabled ones do better).
///    Saved as a reference photo, credited with its site in the spot's note. It's a
///    private reference in the user's own iCloud, like a saved screenshot, and never
///    exported or shared.
/// 2. **Look Around** — Apple's street-level imagery at the coordinates, where covered.
/// 3. **Satellite** — an aerial snapshot of the exact spot, with the pin marked. Often
///    the most useful view of an abandoned place anyway.
///
/// Apple imagery shows what's really at the pin, not what the AI remembers, so it's
/// also a sanity check on the find.
enum SpotPictureService {
    enum Source {
        case web(host: String)
        case lookAround
        case satellite
    }

    /// Longest edge for saved pictures — plenty for a reference, light on iCloud.
    private static let maxPixelSize = 1600

    @MainActor
    @discardableResult
    static func addPicture(to entry: LocationEntryModel, imageURL: String?, in context: ModelContext) async -> Source? {
        let coordinate = CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude)

        if let imageURL, let url = URL(string: imageURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           let data = await downloadImage(url) {
            context.insert(PhotoAsset(imageData: data, isReference: true, entry: entry))
            let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? "the web"
            entry.note = [entry.note, "Photo: \(host) — \(url.absoluteString)"].compactMap { $0 }.joined(separator: "\n\n")
            try? context.save()
            return .web(host: host)
        }

        // Look Around and satellite are context, not "what the shot should look like",
        // so they're saved as ordinary photos — a reference photo you add later still
        // takes over as the spot's preview.
        if let data = await lookAroundSnapshot(at: coordinate) {
            context.insert(PhotoAsset(imageData: data, isReference: false, entry: entry))
            try? context.save()
            return .lookAround
        }
        if let data = await satelliteSnapshot(at: coordinate) {
            context.insert(PhotoAsset(imageData: data, isReference: false, entry: entry))
            try? context.save()
            return .satellite
        }
        return nil
    }

    // MARK: - Sources

    private static func downloadImage(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        // Some sites refuse requests that don't look like a browser.
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType?.hasPrefix("image/") == true,
              data.count < 20_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width >= 200, image.height >= 150 else { return nil } // skip icons/tracking pixels
        return jpeg(image)
    }

    @MainActor
    private static func lookAroundSnapshot(at coordinate: CLLocationCoordinate2D) async -> Data? {
        guard let scene = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene else { return nil }
        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(width: 900, height: 600)
        guard let snapshot = try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot,
              let image = cgImage(snapshot.image) else { return nil }
        return jpeg(image)
    }

    @MainActor
    private static func satelliteSnapshot(at coordinate: CLLocationCoordinate2D) async -> Data? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 450, longitudinalMeters: 450)
        options.preferredConfiguration = MKImageryMapConfiguration()
        options.size = CGSize(width: 900, height: 600)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start(),
              let base = cgImage(snapshot.image) else { return nil }

        // Ring the exact spot so it's clear what the picture is of.
        let width = base.width, height = base.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return jpeg(base) }
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(width) / options.size.width
        let point = snapshot.point(for: coordinate)
        let center = CGPoint(x: point.x * scale, y: CGFloat(height) - point.y * scale) // CG origin is bottom-left
        let radius = 28 * scale
        context.setStrokeColor(CGColor(red: 1, green: 0.84, blue: 0.25, alpha: 1))
        context.setLineWidth(5 * scale)
        context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        return context.makeImage().flatMap(jpeg) ?? jpeg(base)
    }

    // MARK: - Image plumbing

    #if os(iOS)
    private static func cgImage(_ image: UIImage) -> CGImage? { image.cgImage }
    #else
    private static func cgImage(_ image: NSImage) -> CGImage? { image.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    #endif

    private static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
