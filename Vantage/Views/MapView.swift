import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct MapView: View {
    @Query private var entries: [LocationEntryModel]
    @Query(sort: \TripModel.createdDate) private var trips: [TripModel]
    @State private var selectedEntry: LocationEntryModel?
    @State private var tagFilter: String?
    @State private var tripFilter: TripModel?
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var allTags: [String] {
        Array(Set(entries.flatMap(\.tags))).sorted()
    }

    private var filteredEntries: [LocationEntryModel] {
        entries.filter { entry in
            (tagFilter == nil || entry.tags.contains(tagFilter!))
                && (tripFilter == nil || entry.tripID == tripFilter!.id)
        }
    }

    private func markerTitle(for entry: LocationEntryModel) -> String {
        let name = entry.title?.isEmpty == false ? entry.title! : "Spot"
        guard let suggestion = entry.goldenHourSuggestion else { return name }
        return "\(name) · best light \(suggestion.time.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition, selection: $selectedEntry) {
                UserAnnotation()
                ForEach(filteredEntries) { entry in
                    Marker(
                        markerTitle(for: entry),
                        coordinate: CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude)
                    )
                    .tint(AppTheme.cobalt)
                    .tag(entry)
                }
            }
            .mapControls {
                MapUserLocationButton()
            }
            .tint(AppTheme.cobalt)
            .navigationTitle("Map")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .trailingBar) {
                    Menu {
                        Button("All Tags") { tagFilter = nil }
                        ForEach(allTags, id: \.self) { tag in
                            Button(tag) { tagFilter = tag }
                        }
                    } label: {
                        Label(tagFilter ?? "Tag", systemImage: "tag")
                    }
                }
                ToolbarItem(placement: .trailingBar) {
                    Menu {
                        Button("All Trips") { tripFilter = nil }
                        ForEach(trips) { trip in
                            Button(trip.name) { tripFilter = trip }
                        }
                    } label: {
                        Label(tripFilter?.name ?? "Trip", systemImage: "signpost.right.and.left")
                    }
                }
            }
            .sheet(item: $selectedEntry) { entry in
                EntryDetailView(entry: entry)
            }
        }
    }
}
