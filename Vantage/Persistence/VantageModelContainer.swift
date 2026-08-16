import SwiftData

/// Single shared container so the main app, the widget extension, and Siri
/// (via App Intents running in-process) all read and write the same store.
enum VantageModelContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: LocationEntryModel.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
