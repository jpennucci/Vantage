import SwiftUI

/// Small cross-platform shims so views shared between the iOS app and the Mac
/// companion app (MapView, TripsView, EntryDetailView) don't need scattered #if guards.
extension ToolbarItemPlacement {
    static var trailingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
}

/// Decodes a PhotoAsset's stored bytes into a SwiftUI Image regardless of platform
/// (UIImage on iOS, NSImage on macOS). PhotoAsset marks its data .externalStorage,
/// so SwiftData's CloudKit mirroring syncs it as a CKAsset — this is what makes
/// photos actually show up on the Mac now, unlike the old local-file-URL approach.
func loadPhoto(from data: Data) -> Image? {
    #if os(iOS)
    guard let uiImage = UIImage(data: data) else { return nil }
    return Image(uiImage: uiImage)
    #else
    guard let nsImage = NSImage(data: data) else { return nil }
    return Image(nsImage: nsImage)
    #endif
}

func copyToClipboard(_ text: String) {
    #if os(iOS)
    UIPasteboard.general.string = text
    #else
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
}
