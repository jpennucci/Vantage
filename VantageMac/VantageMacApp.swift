import SwiftData
import SwiftUI

@main
struct VantageMacApp: App {
    init() {
        #if DEBUG
        // Before anything touches VantageModelContainer.shared / the real store.
        if CloudKitSchemaInitializer.isRequested {
            CloudKitSchemaInitializer.run()
        }
        #endif
        ScreenshotSeedData.seedIfNeeded(context: VantageModelContainer.shared.mainContext)
        Task { @MainActor in
            await ScreenshotTripSeed.seedIfNeeded(context: VantageModelContainer.shared.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup("Photo Point") {
            MacContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(VantageModelContainer.shared)
        .commands {
            MacCommands()
        }

        WindowGroup("Trip Planner", id: TripPlannerView.windowID, for: UUID.self) { $tripID in
            TripPlannerView(tripID: $tripID)
                .preferredColorScheme(.dark)
        }
        .modelContainer(VantageModelContainer.shared)
        .defaultSize(width: 1100, height: 720)

        Window("Photo Point Help", id: MacHelpView.windowID) {
            MacHelpView()
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 860, height: 620)
    }
}
