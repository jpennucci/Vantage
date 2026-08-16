import SwiftData

/// Single shared container so the main app, the widget extension, and Siri
/// (via App Intents running in-process) all read and write the same store.
/// CloudKit-backed so entries sync across the user's own devices (step 14 in the
/// build order) — every model property already has a default value and nothing
/// is marked `.unique`, which SwiftData's CloudKit mirroring requires.
enum VantageModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([LocationEntryModel.self, TripModel.self])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
