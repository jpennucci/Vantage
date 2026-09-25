import AppKit

/// Screenshot mode only: sizes a window to exactly 1440×900 points — 2880×1800 pixels
/// on a Retina display, one of the Mac App Store's accepted screenshot sizes.
enum ScreenshotWindow {
    @MainActor
    static func fit(titled prefix: String? = nil) {
        guard ScreenshotSeedData.isScreenshotMode else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if prefix == nil {
                // An empty planner window restored from an earlier session would steal
                // focus and leave the main window drawn inactive (washed-out sidebar).
                NSApp.windows.filter { $0.title == "Trip Planner" }.forEach { $0.close() }
            }
            let targets = NSApp.windows.filter { $0.isVisible && (prefix == nil || $0.title.hasPrefix(prefix!)) }
            for window in targets {
                window.setFrame(NSRect(x: 80, y: 80, width: 1440, height: 900), display: true)
            }
            NSApp.activate()
            targets.last?.makeKeyAndOrderFront(nil)
        }
    }
}
