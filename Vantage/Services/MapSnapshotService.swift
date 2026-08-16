import MapKit
import UIKit

/// Renders a small satellite snapshot of an entry's coordinates as a list-thumbnail
/// fallback when there's no captured photo — free (MapKit, no API key), unlike a real
/// Street View image which needs Google's billed Static Street View API.
enum MapSnapshotService {
    private static var cacheDirectory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("MapSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// Cached to disk by entry ID so the same spot isn't re-rendered every time the
    /// list scrolls it back into view.
    static func snapshot(for entryID: UUID, latitude: Double, longitude: Double) async -> UIImage? {
        let cacheURL = cacheDirectory.appendingPathComponent("\(entryID.uuidString).jpg")
        if let cached = UIImage(contentsOfFile: cacheURL.path) {
            return cached
        }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: 400,
            longitudinalMeters: 400
        )
        options.size = CGSize(width: 120, height: 120)
        options.mapType = .satellite

        guard let snapshot = try? await MKMapSnapshotter(options: options).start(),
              let data = snapshot.image.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        try? data.write(to: cacheURL)
        return snapshot.image
    }
}
