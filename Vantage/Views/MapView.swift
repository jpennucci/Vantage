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
    #else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    // Sun overlay (toolbar "Sun" toggle) — see TripPlanning/SunOverlay.swift.
    @State private var showsSun = false
    @State private var sunDay = Date()
    @State private var sunMinute: Double = 18 * 60
    @State private var sunTimeZone: TimeZone = .current
    @State private var visibleCenter: CLLocationCoordinate2D?

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

    /// A planning tool: on the Mac and iPad-sized screens, not the iPhone, which stays
    /// focused on capturing and the day's plan.
    private var sunFeatureAvailable: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    /// Per-spot sun lines only make sense once zoomed in enough that they don't all
    /// pile on top of each other (and the single map-center sun calculation holds).
    private var showsSunLines: Bool { visibleSpan < 2 }

    private var sunSnapshot: SunOverlaySnapshot? {
        guard showsSun, sunFeatureAvailable, let visibleCenter else { return nil }
        return SunOverlaySnapshot(center: visibleCenter, day: sunDay, minuteOfDay: sunMinute, timeZone: sunTimeZone)
    }

    /// Spots in view, capped so a dense area doesn't turn into a hairball of lines.
    private var sunLineEntries: [LocationEntryModel] {
        guard let visibleCenter else { return [] }
        let half = visibleSpan / 2
        return filteredEntries
            .filter { abs($0.latitude - visibleCenter.latitude) < half && abs($0.longitude - visibleCenter.longitude) < half * 2 }
            .prefix(60)
            .map { $0 }
    }

    /// Rounded to ~1°, so panning within an area doesn't re-run the lookup.
    private var sunTimeZoneKey: String {
        guard showsSun, let visibleCenter else { return "" }
        return "\(visibleCenter.latitude.rounded()),\(visibleCenter.longitude.rounded())"
    }

    private func lookUpSunTimeZone() async {
        guard showsSun, let visibleCenter else { return }
        let location = CLLocation(latitude: visibleCenter.latitude, longitude: visibleCenter.longitude)
        if let zone = try? await CLGeocoder().reverseGeocodeLocation(location).first?.timeZone {
            sunTimeZone = zone
        }
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
                    if let sun = sunSnapshot, showsSunLines {
                        ForEach(sunLineEntries) { entry in
                            let origin = CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude)
                            // ~12% of the visible height, so lines stay readable at any zoom.
                            let length = visibleSpan * 111_000 * 0.12
                            if let rise = sun.sunriseAzimuth {
                                MapPolyline(coordinates: [origin, SunGeometry.destination(from: origin, bearing: rise, meters: length * 0.8)])
                                    .stroke(Color.orange.opacity(0.75), lineWidth: 1.5)
                            }
                            if let set = sun.sunsetAzimuth {
                                MapPolyline(coordinates: [origin, SunGeometry.destination(from: origin, bearing: set, meters: length * 0.8)])
                                    .stroke(Color.red.opacity(0.7), lineWidth: 1.5)
                            }
                            if sun.position.elevationDegrees > -0.833 {
                                MapPolyline(coordinates: [origin, SunGeometry.destination(from: origin, bearing: sun.position.azimuthDegrees, meters: length)])
                                    .stroke(AppTheme.apertureGold, lineWidth: 3)
                                // Shadows run away from the sun, longer the lower it is.
                                let shadowScale = min(max(1 / tan(max(sun.position.elevationDegrees, 1) * .pi / 180), 0.3), 2.5) / 2.5
                                MapPolyline(coordinates: [origin, SunGeometry.destination(from: origin, bearing: sun.position.azimuthDegrees + 180, meters: length * shadowScale)])
                                    .stroke(Color.black.opacity(0.75), style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                            }
                        }
                    }
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
                    visibleCenter = context.region.center
                }
                .onAppear { applyFocus() }
                .onChange(of: focusRequest) { applyFocus() }
                .mapControls {
                    MapUserLocationButton()
                }
                .task(id: sunTimeZoneKey) {
                    await lookUpSunTimeZone()
                }
                .overlay(alignment: .bottom) {
                    if let sun = sunSnapshot {
                        SunOverlayPanel(
                            day: $sunDay,
                            minuteOfDay: $sunMinute,
                            snapshot: sun,
                            timeZone: sunTimeZone,
                            showsLines: showsSunLines
                        )
                    }
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
                if sunFeatureAvailable {
                ToolbarItem(placement: .trailingBar) {
                    Toggle(isOn: $showsSun.animation()) {
                        Label("Sun", systemImage: showsSun ? "sun.max.fill" : "sun.max")
                    }
                    .help("Show where the sun is — and where shadows fall — at each spot for any date and time")
                    .onChange(of: showsSun) {
                        if showsSun {
                            // Start at "now" in the map area's time zone.
                            sunDay = Date()
                            sunMinute = min(Date().timeIntervalSince(SunOverlaySnapshot.dayStart(Date(), in: sunTimeZone)) / 60, 1439)
                        }
                    }
                }
                }
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
