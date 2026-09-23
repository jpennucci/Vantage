import ImageIO
import SwiftUI

/// Downsampled, memory-cached thumbnails for map pins. Decoding every full-size photo
/// on each map redraw would stall panning, so each photo is decoded once per size via
/// ImageIO (which never materializes the full-resolution bitmap) and kept in an NSCache
/// that the system can purge under memory pressure.
enum PhotoThumbnailCache {
    private static let cache = NSCache<NSString, CGImage>()

    static func thumbnail(for photo: PhotoAsset, maxPixelSize: Int) -> Image? {
        let key = "\(photo.id.uuidString)-\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) {
            return Image(decorative: cached, scale: 1)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let data = photo.imageData,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache.setObject(image, forKey: key)
        return Image(decorative: image, scale: 1)
    }
}

extension LocationEntryModel {
    /// The photo that best represents the spot on a map: a reference image (e.g. a
    /// Street View screenshot of what the shot should look like) first, since that's
    /// what the spot is *for*; otherwise the newest photo taken there.
    var previewPhoto: PhotoAsset? {
        let withData = (photos ?? []).filter { $0.imageData != nil }
        return withData.filter(\.isReference).max { $0.createdDate < $1.createdDate }
            ?? withData.max { $0.createdDate < $1.createdDate }
    }
}
