import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// A request from outside the map (the Mac sidebar's "Show on Map") to move the camera
/// to one or more spots. MapView clears it once applied, so asking for the same spot
/// again later still moves the camera, and the map doesn't jump back to an old request
/// when it reappears.
struct MapFocusRequest: Equatable {
    let entryIDs: [UUID]
}

struct MapView: View {
    @Binding var focusRequest: MapFocusRequest?
    @Query private var entries: [LocationEntryModel]
    @Query(sort: \TripModel.createdDate) private var trips: [TripModel]
    @State private var selectedEntry: LocationEntryModel?
    @State private var tagFilter: String?
    @State private var tripFilter: TripModel?
    @State private var cameraPosition: MapCameraPosition = .automatic
    /// Latitude span of the visible region — photo thumbnails replace plain pins once
    /// this is small enough (≈ neighborhood level) that pins rarely overlap.
    @State private var visibleSpan: Double = 180
    @State private var hoveredEntryID: UUID?
    #if os(macOS)
    @Environment(\.modelContext) private var modelContext
    /// Last pointer position over the map — SwiftUI's contextMenu doesn't report where
    /// the right-click landed, so "Add Spot Here" uses the most recent hover point.
    @State private var hoverPoint: CGPoint?
    @State private var isDropTargeted = false
    #endif

    init(focusRequest: Binding<MapFocusRequest?> = .constant(nil)) {
        _focusRequest = focusRequest
    }

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

    /// One spot: town-level zoom (~8 km across) — close enough to see where it is, wide
    /// enough to keep surrounding context — and its preview card pops up briefly so the
    /// pin is easy to pick out. Several spots: fit them all with some padding.
    private func applyFocus() {
        guard let request = focusRequest else { return }
        focusRequest = nil
        let targets = entries.filter { request.entryIDs.contains($0.id) }
        guard !targets.isEmpty else { return }

        // The map has its own tag/trip filter; don't fly to a pin it's hiding.
        let visibleIDs = Set(filteredEntries.map(\.id))
        if targets.contains(where: { !visibleIDs.contains($0.id) }) {
            tagFilter = nil
            tripFilter = nil
        }

        let region: MKCoordinateRegion
        if targets.count == 1, let target = targets.first {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
                latitudinalMeters: 8000,
                longitudinalMeters: 8000
            )
        } else {
            let latitudes = targets.map(\.latitude), longitudes = targets.map(\.longitude)
            let minLat = latitudes.min()!, maxLat = latitudes.max()!
            let minLng = longitudes.min()!, maxLng = longitudes.max()!
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
                span: MKCoordinateSpan(
                    latitudeDelta: max((maxLat - minLat) * 1.4, 0.05),
                    longitudeDelta: max((maxLng - minLng) * 1.4, 0.05)
                )
            )
        }
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraPosition = .region(region)
        }

        if targets.count == 1, let target = targets.first, target.previewPhoto != nil {
            hoveredEntryID = target.id
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if hoveredEntryID == target.id { hoveredEntryID = nil }
            }
        }
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $cameraPosition, selection: $selectedEntry) {
                    UserAnnotation()
                    ForEach(filteredEntries) { entry in
                        Annotation(
                            markerTitle(for: entry),
                            coordinate: CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude),
                            anchor: .bottom
                        ) {
                            SpotMapPin(
                                entry: entry,
                                showsThumbnail: visibleSpan < 0.05,
                                isHovered: hoveredEntryID == entry.id
                            )
                            .onHover { hovering in
                                if hovering {
                                    hoveredEntryID = entry.id
                                } else if hoveredEntryID == entry.id {
                                    hoveredEntryID = nil
                                }
                            }
                            .onTapGesture { selectedEntry = entry }
                        }
                        .tag(entry)
                    }
                }
                .onMapCameraChange { context in
                    visibleSpan = context.region.span.latitudeDelta
                }
                .onAppear { applyFocus() }
                .onChange(of: focusRequest) { applyFocus() }
                .mapControls {
                    MapUserLocationButton()
                }
                #if os(macOS)
                .onContinuousHover { phase in
                    if case .active(let point) = phase { hoverPoint = point }
                }
                .contextMenu {
                    Button {
                        if let hoverPoint, let coordinate = proxy.convert(hoverPoint, from: .local) {
                            selectedEntry = MacSpotDrop.createSpot(at: coordinate, in: modelContext)
                        }
                    } label: {
                        Label("Add Spot Here", systemImage: "mappin.and.ellipse")
                    }
                }
                .onDrop(of: MacSpotDrop.acceptedTypes, isTargeted: $isDropTargeted) { providers, location in
                    let dropCoordinate = proxy.convert(location, from: .local)
                    Task { @MainActor in
                        switch await MacSpotDrop.load(from: providers) {
                        case .image(let data):
                            guard let dropCoordinate else { return }
                            selectedEntry = MacSpotDrop.createSpot(at: dropCoordinate, photo: data, in: modelContext)
                        case .mapsLink(let link):
                            selectedEntry = await MacSpotDrop.createSpot(fromMapsLink: link, in: modelContext)
                        case nil:
                            break
                        }
                    }
                    return true
                }
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(AppTheme.cobalt, lineWidth: 3)
                            .overlay(alignment: .top) {
                                Text("Drop a photo to start a new spot here")
                                    .font(.callout.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.regularMaterial, in: Capsule())
                                    .padding(.top, 12)
                            }
                            .allowsHitTesting(false)
                    }
                }
                #endif
            }
            .tint(AppTheme.cobalt)
            .navigationTitle("Map")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .trailingBar) {
                    Menu {
                        Menu {
                            Button("All Tags") { tagFilter = nil }
                            ForEach(allTags, id: \.self) { tag in
                                Button(tag) { tagFilter = tag }
                            }
                        } label: {
                            Label(tagFilter ?? "Tag", systemImage: "tag")
                        }
                        Menu {
                            Button("All Trips") { tripFilter = nil }
                            ForEach(trips) { trip in
                                Button(trip.name) { tripFilter = trip }
                            }
                        } label: {
                            Label(tripFilter?.name ?? "Trip", systemImage: "signpost.right.and.left")
                        }
                    } label: {
                        Label("Filter", systemImage: (tagFilter != nil || tripFilter != nil) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(item: $selectedEntry) { entry in
                EntryDetailView(entry: entry)
            }
        }
    }
}

/// A spot's map pin: a plain cobalt pin when zoomed out, the spot's photo once zoomed
/// in far enough to see it, and — on pointer hover (Mac, or iPad with a trackpad) — a
/// larger preview card above the pin at any zoom level. With `anchor: .bottom` the card
/// grows upward, so the pin's point stays on the spot's coordinate.
private struct SpotMapPin: View {
    let entry: LocationEntryModel
    let showsThumbnail: Bool
    let isHovered: Bool

    var body: some View {
        let photo = entry.previewPhoto
        VStack(spacing: 4) {
            if isHovered, let photo, let preview = PhotoThumbnailCache.thumbnail(for: photo, maxPixelSize: 480) {
                VStack(alignment: .leading, spacing: 4) {
                    preview
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(entry.title?.isEmpty == false ? entry.title! : "Spot")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 6)
                .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
            }

            if showsThumbnail, let photo, let thumbnail = PhotoThumbnailCache.thumbnail(for: photo, maxPixelSize: 160) {
                thumbnail
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.cobalt, lineWidth: 2.5))
                    .shadow(radius: 3)
            } else {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, AppTheme.cobalt)
                    .shadow(radius: 2)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
