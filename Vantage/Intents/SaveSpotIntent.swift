import AppIntents

/// Runs the exact same capture path as the in-app button. `openAppWhenRun` is true
/// because a one-shot GPS/heading read needs the app in the foreground to reliably
/// prompt for location permission and get a fix — this trades a brief app launch for
/// using the same proven CoreLocation code path everywhere, rather than a second,
/// harder-to-verify background-capture implementation.
struct SaveSpotIntent: AppIntent {
    static var title: LocalizedStringResource = "Save This Spot"
    static var description = IntentDescription("Saves your current location, heading, and timestamp to Vantage.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Name")
    var name: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        let captureService = LocationCaptureService()
        captureService.requestPermissionIfNeeded()
        await CaptureAndSaveUseCase.run(using: captureService, title: name)
        return .result()
    }
}
