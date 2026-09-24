import MapKit
import SwiftData
import SwiftUI

/// "Find Along the Route": describe a drive, say what you're into, and work through
/// the route one segment at a time — copy a ready-made prompt into an AI chat tool
/// (ideally one with web search, so it can dig through forums and blogs), paste the
/// reply back, and every find lands in the trip placed at its mile along the route.
///
/// Built for the Route 66 problem: the specific, obscure stops that take hours of
/// searching to find by hand. Shared by the iPhone (trip screen) and the Mac (the
/// Trip Planner window's "Along the Route" tab).
struct RouteFinderView: View {
    @Bindable var trip: TripModel

    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [LocationEntryModel]

    @State private var route = TripRoute()
    @State private var geometry: RouteGeometry?
    @State private var isCalculating = false
    @State private var routeError: String?
    /// Place names at each segment boundary (count = segments + 1).
    @State private var boundaryNames: [Int: String] = [:]
    @State private var startText = ""
    @State private var endText = ""
    @State private var waypointText = ""
    @State private var isResolving = false
    @State private var copiedItem: String?
    @State private var importingSegment: Int?
    @State private var message: String?
    @State private var openEntry: LocationEntryModel?
    @State private var cameraPosition: MapCameraPosition = .automatic

    private static let metersPerMile = RouteFinderService.metersPerMile

    // MARK: - Derived

    private var segments: [RouteSegment] {
        geometry?.segments(miles: route.segmentMiles) ?? []
    }

    private var tripEntries: [LocationEntryModel] {
        allEntries.filter { $0.tripID == trip.id }
    }

    private struct Find: Identifiable {
        var id: UUID { entry.id }
        let entry: LocationEntryModel
        let placement: RouteGeometry.Placement
    }

    /// Every spot in the trip, placed along the route in driving order.
    private var finds: [Find] {
        guard let geometry else { return [] }
        return tripEntries
            .compactMap { entry in
                geometry.place(CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude))
                    .map { Find(entry: entry, placement: $0) }
            }
            .sorted { $0.placement.alongMeters < $1.placement.alongMeters }
    }

    private func findCount(in segment: RouteSegment) -> Int {
        finds.filter { segment.contains($0.placement.alongMeters) }.count
    }

    private func name(atBoundary index: Int) -> String {
        boundaryNames[index] ?? (index == 0 ? route.start?.name : index == segments.count ? route.end?.name : nil) ?? "mile \(Int(boundaryMeters(index) / Self.metersPerMile))"
    }

    private func boundaryMeters(_ index: Int) -> Double {
        index < segments.count ? (segments[safe: index]?.startMeters ?? 0) : (segments.last?.endMeters ?? 0)
    }

    private var routeKey: String {
        ([route.start, route.end] + route.waypoints.map { Optional($0) })
            .map { $0.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) } ?? "-" }
            .joined(separator: ">")
    }

    // MARK: - Body

    var body: some View {
        Form {
            routeSection
            interestsSection
            if geometry != nil {
                segmentsSection
                findsSection
                mapSection
            }
        }
        .formStyle(.grouped)
        .onAppear { route = trip.route }
        .onChange(of: route) {
            if trip.route != route { trip.route = route }
        }
        .onChange(of: trip.routeData) {
            // Edited on another device.
            if trip.route != route { route = trip.route }
        }
        .task(id: routeKey) { await calculate() }
        .task(id: "\(routeKey)|\(route.segmentMiles)|\(geometry == nil)") { await nameBoundaries() }
        .sheet(item: $openEntry) { entry in
            EntryDetailView(entry: entry)
        }
        .alert("Along the Route", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: - Route

    private var routeSection: some View {
        Section {
            placeRow("Start", place: route.start, text: $startText) { route.start = $0 }
            placeRow("End", place: route.end, text: $endText) { route.end = $0 }

            TextField("How to get there (optional) — e.g. “Stay on historic Route 66”", text: $route.guidance, axis: .vertical)

            ForEach(Array(route.waypoints.enumerated()), id: \.offset) { index, waypoint in
                HStack {
                    Label(waypoint.name, systemImage: "\(index + 1).circle")
                    Spacer()
                    Button {
                        route.waypoints.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onMove { route.waypoints.move(fromOffsets: $0, toOffset: $1) }

            HStack {
                TextField("Add a town to route through", text: $waypointText)
                    .onSubmit { Task { await addWaypoint() } }
                if isResolving { ProgressView().controlSize(.small) }
            }

            if route.hasEnds {
                HStack {
                    Button {
                        copy(RouteFinderService.waypointPrompt(for: route), as: "waypoints")
                    } label: {
                        Label(copiedItem == "waypoints" ? "Copied" : "Copy Waypoint Prompt", systemImage: copiedItem == "waypoints" ? "checkmark" : "doc.on.doc")
                    }
                    Button {
                        pasteWaypoints()
                    } label: {
                        Label("Paste Waypoints", systemImage: "doc.on.clipboard")
                    }
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text("Route")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if isCalculating {
                    Label("Calculating the route…", systemImage: "hourglass")
                } else if let geometry {
                    Text("\(Int(geometry.totalMeters / Self.metersPerMile).formatted()) miles · \(segments.count) segment\(segments.count == 1 ? "" : "s") of about \(Int(route.segmentMiles)) miles")
                } else if let routeError {
                    Text(routeError).foregroundStyle(AppTheme.warningRed)
                }
                Text("Following a specific road, like historic Route 66? Navigation takes the fastest highway unless you add towns to route through. Copy the waypoint prompt into an AI chat, then paste its reply to fill them in.")
            }
            .font(.caption)
        }
    }

    private func placeRow(_ label: String, place: TripPlanStart?, text: Binding<String>, set: @escaping (TripPlanStart?) -> Void) -> some View {
        HStack {
            Text(label).frame(width: 44, alignment: .leading)
            if let place {
                Label(place.name, systemImage: "mappin.circle.fill")
                    .foregroundStyle(AppTheme.cobaltLight)
                Spacer()
                Button {
                    set(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                TextField("City, address, or Google Maps link", text: text)
                    .onSubmit {
                        Task {
                            isResolving = true
                            defer { isResolving = false }
                            if let resolved = await RouteFinderService.resolvePlace(text.wrappedValue) {
                                set(resolved)
                                text.wrappedValue = ""
                            } else {
                                message = "Couldn't find “\(text.wrappedValue)” — try a city and state, a full address, or a Google Maps link."
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Interests

    private var interestsSection: some View {
        Section {
            FlowLayout {
                ForEach(TripRoute.suggestedInterests, id: \.self) { interest in
                    ChipToggle(title: interest, isOn: Binding(
                        get: { route.interests.contains(interest) },
                        set: { isOn in
                            if isOn { route.interests.append(interest) } else { route.interests.removeAll { $0 == interest } }
                        }
                    ))
                }
            }
            .padding(.vertical, 4)
            TextField("Anything else, comma separated — e.g. “old barns, drive-in theaters”", text: $route.customInterests, axis: .vertical)
            Stepper("Within \(Int(route.maxDetourMiles)) miles of the route", value: $route.maxDetourMiles, in: 1...100, step: 5)
            Stepper("Segments of about \(Int(route.segmentMiles)) miles", value: $route.segmentMiles, in: 50...600, step: 25)
        } header: {
            Text("What to Find")
        } footer: {
            Text("Shorter segments give the AI a smaller stretch to dig into, so you'll usually get more (and more obscure) finds per mile.")
                .font(.caption)
        }
    }

    // MARK: - Segments

    private var segmentsSection: some View {
        Section {
            ForEach(segments) { segment in
                let done = route.completedSegments.contains(segment.number)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: done ? "checkmark.circle.fill" : "\(segment.number).circle")
                            .foregroundStyle(done ? AppTheme.shutterGreen : AppTheme.cobaltLight)
                        Text("\(name(atBoundary: segment.number - 1)) → \(name(atBoundary: segment.number))")
                            .font(.headline)
                    }
                    Text("\(Int((segment.endMeters - segment.startMeters) / Self.metersPerMile)) mi · miles \(Int(segment.startMeters / Self.metersPerMile))–\(Int(segment.endMeters / Self.metersPerMile)) · \(findCount(in: segment)) found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button {
                            copySegmentPrompt(segment)
                        } label: {
                            Label(copiedItem == "segment\(segment.number)" ? "Copied" : "Copy Prompt", systemImage: copiedItem == "segment\(segment.number)" ? "checkmark" : "doc.on.doc")
                        }
                        Button {
                            Task { await pasteResults(for: segment) }
                        } label: {
                            if importingSegment == segment.number {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Paste Results", systemImage: "doc.on.clipboard")
                            }
                        }
                        .disabled(importingSegment != nil)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Search the Route, One Segment at a Time")
        } footer: {
            Text("For each segment: Copy Prompt → paste it into Claude, ChatGPT, or another AI chat (turn on web search if it has it) → copy the whole reply → Paste Results. Finds are added to this trip, and any whose address and coordinates disagree are tagged “unverified”.")
                .font(.caption)
        }
    }

    // MARK: - Finds

    private var findsSection: some View {
        Section {
            if finds.isEmpty {
                Text("Nothing yet — work through a segment above.")
                    .foregroundStyle(.secondary)
            }
            ForEach(finds) { find in
                let offMiles = find.placement.offRouteMeters / Self.metersPerMile
                let tooFar = offMiles > route.maxDetourMiles
                Button {
                    openEntry = find.entry
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(Int(find.placement.alongMeters / Self.metersPerMile))")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .frame(minWidth: 40)
                            .padding(.vertical, 3)
                            .background(AppTheme.cobalt.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                            .help("Mile along the route")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(find.entry.title?.isEmpty == false ? find.entry.title! : "Untitled Spot")
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                Text(offMiles < 0.5 ? "On the route" : String(format: "%.1f mi off route", offMiles))
                                    .foregroundStyle(tooFar ? .orange : .secondary)
                                if find.entry.tags.contains(SpotImportService.unverifiedTag) {
                                    Label("Unverified", systemImage: "questionmark.circle")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        modelContext.delete(find.entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Along the Route (\(finds.count))")
        } footer: {
            Text("Every spot in this trip, in driving order, with the mile where it falls along the route. Orange means farther off the route than you asked for — or that its location couldn't be verified, so check it before you detour.")
                .font(.caption)
        }
    }

    private var mapSection: some View {
        Section {
            Map(position: $cameraPosition) {
                if let geometry {
                    ForEach(Array(geometry.polylines.enumerated()), id: \.offset) { _, polyline in
                        MapPolyline(polyline).stroke(AppTheme.cobalt, lineWidth: 4)
                    }
                }
                ForEach(finds) { find in
                    Marker(
                        find.entry.title ?? "Spot",
                        coordinate: CLLocationCoordinate2D(latitude: find.entry.latitude, longitude: find.entry.longitude)
                    )
                    .tint(find.placement.offRouteMeters / Self.metersPerMile > route.maxDetourMiles ? .orange : AppTheme.apertureGold)
                }
            }
            .frame(height: 320)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - Actions

    private func calculate() async {
        guard route.hasEnds else { geometry = nil; return }
        isCalculating = true
        routeError = nil
        defer { isCalculating = false }
        geometry = await RouteFinderService.geometry(for: route)
        if geometry == nil {
            routeError = "Couldn't calculate a driving route between those places."
        }
        cameraPosition = .automatic
    }

    /// Sequential — reverse geocoding is rate limited.
    private func nameBoundaries() async {
        guard let geometry else { return }
        var names: [Int: String] = [:]
        for index in 0...segments.count {
            if Task.isCancelled { return }
            if index == 0, let start = route.start { names[0] = start.name; continue }
            if index == segments.count, let end = route.end { names[index] = end.name; continue }
            if let name = await RouteFinderService.placeName(near: geometry.coordinate(atMeters: boundaryMeters(index))) {
                names[index] = name
            }
        }
        boundaryNames = names
    }

    private func addWaypoint() async {
        isResolving = true
        defer { isResolving = false }
        if let place = await RouteFinderService.resolvePlace(waypointText) {
            route.waypoints.append(place)
            waypointText = ""
        } else {
            message = "Couldn't find “\(waypointText)”."
        }
    }

    private func pasteWaypoints() {
        guard let text = pasteFromClipboard(), let waypoints = RouteFinderService.parseWaypoints(text) else {
            message = "Couldn't find waypoints in the clipboard — copy the AI's whole reply and try again."
            return
        }
        route.waypoints = waypoints
        message = "Added \(waypoints.count) waypoints. The route is being recalculated through them."
    }

    private func copySegmentPrompt(_ segment: RouteSegment) {
        guard let geometry else { return }
        let prompt = RouteFinderService.segmentPrompt(
            route: route,
            geometry: geometry,
            segment: segment,
            segmentCount: segments.count,
            fromName: name(atBoundary: segment.number - 1),
            toName: name(atBoundary: segment.number),
            existingTitles: tripEntries.compactMap(\.title)
        )
        copy(prompt, as: "segment\(segment.number)")
    }

    private func pasteResults(for segment: RouteSegment) async {
        guard let text = pasteFromClipboard(), let data = text.data(using: .utf8) else {
            message = "Nothing to paste — copy the AI's reply first."
            return
        }
        importingSegment = segment.number
        defer { importingSegment = nil }
        let summary = await SpotImportService.importSpots(
            from: data,
            into: modelContext,
            addingTo: trip,
            extraTags: [RouteFinderService.alongRouteTag],
            verifyAddresses: true
        )
        if summary.hasPrefix("Imported"), !route.completedSegments.contains(segment.number) {
            route.completedSegments.append(segment.number)
        }
        message = summary
    }

    private func copy(_ text: String, as item: String) {
        copyToClipboard(text)
        copiedItem = item
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if copiedItem == item { copiedItem = nil }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
