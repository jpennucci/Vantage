import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var selection = ProcessInfo.processInfo.environment["VANTAGE_SCREENSHOT_SCREEN"] == "map" ? 1 : 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \TripModel.createdDate, order: .reverse) private var trips: [TripModel]
    @State private var plannerTripID: UUID?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView(selection: $selection) {
            CaptureView()
                .tabItem { Label("Capture", systemImage: "mappin.circle.fill") }
                .tag(0)
            MapView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(1)
            // Planning is an iPad/Mac job — the full Trip Planner only appears when
            // there's room for it, so the iPhone stays simple (its trips live under
            // Trips → Plan & Pack instead).
            if horizontalSizeClass == .regular {
                NavigationStack {
                    TripPlannerView(tripID: $plannerTripID)
                }
                .tabItem { Label("Plan", systemImage: "calendar.badge.clock") }
                .tag(2)
            }
        }
        .onAppear {
            if plannerTripID == nil { plannerTripID = trips.first?.id }
        }
        .task {
            if ScreenshotScreen.hasPrefix("plan") || ScreenshotScreen.is("finds-plan") {
                selection = 2
                plannerTripID = await ScreenshotScreen.demoTrip(in: modelContext)?.id
            } else if ScreenshotScreen.is("sun") {
                selection = 1
            }
        }
        .tint(AppTheme.cobalt)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LocationEntryModel.self, TripModel.self], inMemory: true)
}
