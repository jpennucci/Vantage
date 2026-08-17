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
    /// True for a reference/inspiration image (found online, saved to emulate later),
    /// false for a quick field-capture photo — same storage, just two separate
    /// sections in the UI rather than a second model.
    var isReference: Bool = false
    var entry: LocationEntryModel?

    init(id: UUID = UUID(), imageData: Data?, createdDate: Date = Date(), isReference: Bool = false, entry: LocationEntryModel? = nil) {
        self.id = id
        self.imageData = imageData
        self.createdDate = createdDate
        self.isReference = isReference
        self.entry = entry
    }
}
