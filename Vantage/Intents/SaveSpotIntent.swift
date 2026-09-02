import AppIntents
#if os(watchOS)
import WatchKit
#endif

/// Runs the exact same capture path as the in-app button. `openAppWhenRun` is true
/// because a one-shot GPS/heading read needs the app in the foreground to reliably
/// prompt for location permission and get a fix — this trades a brief app launch for
/// using the same proven CoreLocation code path everywhere, rather than a second,
/// harder-to-verify background-capture implementation.
struct SaveSpotIntent: AppIntent {
    static var title: LocalizedStringResource = "Save This Spot"
    static var description = IntentDescription("Saves your current location, heading, and timestamp to Photo Point.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Name")
    var name: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let captureService = LocationCaptureService()
        captureService.requestPermissionIfNeeded()
        let entry = await CaptureAndSaveUseCase.run(using: captureService, title: name)
        // Spoken confirmation matters most here — this is the hands-free, eyes-on-the-road
        // path, so hearing it worked (or didn't) matters more than glancing at the screen.
        // On watchOS specifically, also fire a haptic directly from the intent itself —
        // Siri-triggered saves run this without necessarily bringing WatchCaptureView's
        // own success animation/haptic on screen, so this is the one confirmation
        // guaranteed to be felt regardless of whether the app UI actually becomes visible.
        // (The watch face complication no longer routes through here at all — see
        // CaptureWidget.swift for why — so this now only fires for Siri on watchOS.)
        #if os(watchOS)
        WKInterfaceDevice.current().play(entry != nil ? .success : .failure)
        #endif
        if entry != nil {
            return .result(dialog: "Saved to Photo Point.")
        } else {
            return .result(dialog: "Couldn't save that spot — check location access in Photo Point.")
        }
    }
}
