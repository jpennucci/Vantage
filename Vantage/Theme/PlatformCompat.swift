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

/// Loads a photo reference into a SwiftUI Image regardless of platform (UIImage on
/// iOS, NSImage on macOS). Photos captured on iPhone are local-file-only today (not
/// CloudKit-synced), so this will often return nil on the Mac for iPhone-captured
/// entries — that's expected until photo sync is built.
func loadPhoto(at url: URL) -> Image? {
    #if os(iOS)
    guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
    return Image(uiImage: uiImage)
    #else
    guard let nsImage = NSImage(contentsOfFile: url.path) else { return nil }
    return Image(nsImage: nsImage)
    #endif
}
