import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CaptureView()
                .tabItem { Label("Capture", systemImage: "mappin.circle.fill") }
            MapView()
                .tabItem { Label("Map", systemImage: "map") }
        }
        .tint(AppTheme.cobalt)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LocationEntryModel.self, TripModel.self], inMemory: true)
}
