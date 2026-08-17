import SwiftUI

struct ContentView: View {
    @State private var selection = ProcessInfo.processInfo.environment["VANTAGE_SCREENSHOT_SCREEN"] == "map" ? 1 : 0

    var body: some View {
        TabView(selection: $selection) {
            CaptureView()
                .tabItem { Label("Capture", systemImage: "mappin.circle.fill") }
                .tag(0)
            MapView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(1)
        }
        .tint(AppTheme.cobalt)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LocationEntryModel.self, TripModel.self], inMemory: true)
}
