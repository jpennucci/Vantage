import SwiftData
import SwiftUI

@main
struct VantageMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacContentView()
        }
        .modelContainer(VantageModelContainer.shared)
    }
}
