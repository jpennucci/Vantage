import Foundation
import SwiftData

/// Single shared container so the main app, the widget extension, and Siri
/// (via App Intents running in-process) all read and write the same store.
/// CloudKit-backed so entries sync across the user's own devices (step 14 in the
/// build order) — every model property already has a default value and nothing
/// is marked `.unique`, which SwiftData's CloudKit mirroring requires.
///
/// The store file lives in the `group.com.jamespennucci.Vantage` App Group
/// container rather than SwiftData's default per-process location. Without this,
/// each extension (Lock Screen widget, Watch complication) gets its own separate
/// sandboxed store — a save there is invisible to the host app until CloudKit's
/// async export/import round-trip completes, which a short-lived extension
/// process may not survive long enough to even start. Sharing the on-disk file
/// directly makes a capture visible to every process on the same device
/// immediately, independent of CloudKit timing.
enum VantageModelContainer {
    /// Debug builds sync to CloudKit's *Development* environment, TestFlight/App Store
    /// builds to *Production* — but both use the same bundle ID and App Group, so
    /// without separate files a debug build run on a device/Mac that also has the
    /// TestFlight build would open the Production-synced store and mix the two
    /// environments' sync state (seen 2026-09-24: "Change Token Expired", then old
    /// test spots uploaded into Production). "default" matches SwiftData's own
    /// default name, so release builds keep using their existing store file.
    #if DEBUG
    private static let storeName = "debug"
    #else
    private static let storeName = "default"
    #endif

    static let shared: ModelContainer = {
        let schema = Schema([LocationEntryModel.self, TripModel.self, PhotoAsset.self])
        // Plain `url:` + `cloudKitDatabase: .automatic` silently ignores the custom
        // url and falls back to SwiftData's own default per-app location — confirmed
        // by pulling the App Group container straight off a device and finding it
        // untouched after real saves. `groupContainer:` is the API actually meant to
        // combine App Group sharing with CloudKit mirroring.
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            groupContainer: .identifier("group.com.jamespennucci.Vantage"),
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
