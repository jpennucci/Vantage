import UIKit

/// Compresses a captured reference photo for storage on a PhotoAsset. Photos used to
/// be saved to a local file and referenced by URL, which never synced anywhere —
/// PhotoAsset now stores the bytes directly so CloudKit can mirror them.
enum PhotoStorageService {
    static func jpegData(from image: UIImage) -> Data? {
        image.jpegData(compressionQuality: 0.8)
    }
}
