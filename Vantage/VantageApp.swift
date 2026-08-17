import SwiftData
import SwiftUI

@main
struct VantageApp: App {
    init() {
        ScreenshotSeedData.seedIfNeeded(context: VantageModelContainer.shared.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(VantageModelContainer.shared)
    }
}
