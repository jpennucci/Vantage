import AppKit

/// Screenshot mode only: sizes a window to exactly 1440×900 points — 2880×1800 pixels
/// on a Retina display, one of the Mac App Store's accepted screenshot sizes.
enum ScreenshotWindow {
    @MainActor
    static func fit(titled prefix: String? = nil) {
        guard ScreenshotSeedData.isScreenshotMode else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            for window in NSApp.windows where window.isVisible && (prefix == nil || window.title.hasPrefix(prefix!)) {
                window.setFrame(NSRect(x: 80, y: 80, width: 1440, height: 900), display: true)
            }
        }
    }
}
