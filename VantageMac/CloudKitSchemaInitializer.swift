#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Debug-only: pushes the *complete* SwiftData schema (every record type and field)
/// to the CloudKit **Development** environment, so it can then be deployed to
/// Production from the CloudKit Console.
///
/// Why this exists: SwiftData never calls `initializeCloudKitSchema` itself, so the
/// Development schema only ever contained whatever debug builds happened to save.
/// Production was never deployed with `CD_TripModel` at all, and every TestFlight /
/// App Store export batch containing a trip failed with "Cannot create new type
/// CD_TripModel in production schema" — atomically, taking the batch's spots with it.
///
/// Run once from a debug Mac build (debug signing = Development environment):
///   VANTAGE_INIT_CLOUDKIT_SCHEMA=1 "Photo Point.app/Contents/MacOS/Photo Point"
/// Uses a throwaway store in a temp directory, so real local data isn't touched.
/// Apple's documented approach for SwiftData + CloudKit schema initialization.
enum CloudKitSchemaInitializer {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["VANTAGE_INIT_CLOUDKIT_SCHEMA"] == "1"
    }

    static func run() -> Never {
        do {
            let storeURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CloudKitSchemaInit-\(UUID().uuidString).store")
            let description = NSPersistentStoreDescription(url: storeURL)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.jamespennucci.Vantage"
            )
            description.shouldAddStoreAsynchronously = false

            guard let model = NSManagedObjectModel.makeManagedObjectModel(
                for: [LocationEntryModel.self, TripModel.self, PhotoAsset.self, GearItem.self]
            ) else {
                print("SCHEMA-INIT FAILED: couldn't build managed object model")
                exit(1)
            }
            let container = NSPersistentCloudKitContainer(name: "CloudKitSchemaInit", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]

            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }

            try container.initializeCloudKitSchema()
            print("SCHEMA-INIT OK: record types/fields pushed to CloudKit Development")

            if let store = container.persistentStoreCoordinator.persistentStores.first {
                try container.persistentStoreCoordinator.remove(store)
            }
            try? FileManager.default.removeItem(at: storeURL)
            exit(0)
        } catch {
            print("SCHEMA-INIT FAILED: \(error)")
            exit(1)
        }
    }
}
#endif
