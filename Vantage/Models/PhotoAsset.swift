import Foundation
import SwiftData

/// A photo attached to a LocationEntryModel. Stored as its own model (rather than a
/// URL on the entry, which is how this worked before) so SwiftData's CloudKit
/// mirroring can sync the actual image bytes as a CKAsset via .externalStorage —
/// URLs only pointed at a local file, which meant photos never left the device
/// that captured them.
@Model
final class PhotoAsset {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data?
    var createdDate: Date = Date()
    var entry: LocationEntryModel?

    init(id: UUID = UUID(), imageData: Data?, createdDate: Date = Date(), entry: LocationEntryModel? = nil) {
        self.id = id
        self.imageData = imageData
        self.createdDate = createdDate
        self.entry = entry
    }
}
