import SwiftData
import SwiftUI

@main
struct VantageMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(VantageModelContainer.shared)
    }
}
