import SwiftData
import SwiftUI

@main
struct VantageWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchCaptureView()
        }
        .modelContainer(VantageModelContainer.shared)
    }
}
