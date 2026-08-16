import SwiftData

/// Shared by the in-app capture button, the Lock Screen widget button, and the
/// Siri Shortcut so all three entry points save through the exact same path.
@MainActor
enum CaptureAndSaveUseCase {
    @discardableResult
    static func run(using captureService: LocationCaptureService) async -> LocationEntryModel? {
        guard let entry = await captureService.captureLocation() else { return nil }
        VantageModelContainer.shared.mainContext.insert(entry)
        return entry
    }
}
