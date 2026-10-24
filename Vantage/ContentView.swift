import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var selection = ProcessInfo.processInfo.environment["VANTAGE_SCREENSHOT_SCREEN"] == "map" ? 1 : 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \TripModel.createdDate, order: .reverse) private var trips: [TripModel]
    @State private var plannerTripID: UUID?
    /// The planner's trip, opened in the Trips tab when the screen narrows (folding an
    /// iPhone Duo, or iPad split view) while the full planner is showing.
    @State private var foldedPlanTrip: TripModel?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView(selection: $selection) {
            CaptureView()
                .tabItem { Label("Capture", systemImage: "mappin.circle.fill") }
                .tag(0)
            MapView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(1)
            // One Trips tab everywhere, so it never vanishes on a fold: the full Trip
            // Planner where there's room (iPad, unfolded iPhone Duo), the trip list
            // with each trip's itinerary, route and packing on the iPhone.
            Group {
                if horizontalSizeClass == .regular {
                    NavigationStack {
                        TripPlannerView(tripID: $plannerTripID)
                    }
                } else {
                    TripsView(showsDone: false, openTrip: $foldedPlanTrip)
                }
            }
            .tabItem { Label("Trips", systemImage: "signpost.right.and.left") }
            .tag(2)
        }
        .onAppear {
            if plannerTripID == nil { plannerTripID = trips.first?.id }
        }
        // Folding swaps the Trips tab's planner for the trip list: keep the same trip
        // open in it, and hand it back to the planner on unfolding.
        .onChange(of: horizontalSizeClass) {
            if horizontalSizeClass == .regular {
                if let trip = foldedPlanTrip {
                    plannerTripID = trip.id
                    foldedPlanTrip = nil
                }
            } else if selection == 2 {
                foldedPlanTrip = trips.first { $0.id == plannerTripID }
            }
        }
        .task {
            if ScreenshotScreen.hasPrefix("plan") || ScreenshotScreen.is("finds-plan") {
                selection = 2
                plannerTripID = await ScreenshotScreen.demoTrip(in: modelContext)?.id
            } else if ScreenshotScreen.is("sun") {
                selection = 1
            } else if ScreenshotScreen.is("trips-tab") {
                selection = 2
            }
        }
        .tint(AppTheme.cobalt)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LocationEntryModel.self, TripModel.self], inMemory: true)
}
