import MapKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Mac companion — view + light edit of entries synced from the iPhone app (step 15
/// in the build order). No capture flow here: this is a planning/review tool, not
/// a field-capture tool, so there's no "Save This Spot" button.
struct MacContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \LocationEntryModel.timestamp, order: .reverse) private var entries: [LocationEntryModel]
    @Query(sort: \TripModel.createdDate, order: .reverse) private var trips: [TripModel]
    @State private var selection = Set<UUID>()
    @State private var searchText = ""
    @State private var tagFilter: String?
    @State private var tripFilter: TripModel?
    @State private var showingTrips = false
    @State private var showingAddLocation = false
    @State private var showingImporter = false
    @State private var showingImportHelp = false
    @State private var importSummary: String?
    @State private var dropTargetID: UUID?
    @State private var statusMessage: String?
    @State private var mapFocus: MapFocusRequest?
    @State private var findMoreTrip: TripModel?
    @State private var showingGearLibrary = false

    private var allTags: [String] {
        Array(Set(entries.flatMap(\.tags))).sorted()
    }

    private func tripName(for entry: LocationEntryModel) -> String? {
        guard let tripID = entry.tripID else { return nil }
        return trips.first { $0.id == tripID }?.name
    }

    private var selectedEntries: [LocationEntryModel] {
        filteredEntries.filter { selection.contains($0.id) }
    }

    private var filteredEntries: [LocationEntryModel] {
        entries.filter { entry in
            (tagFilter == nil || entry.tags.contains(tagFilter!))
                && (tripFilter == nil || entry.tripID == tripFilter!.id)
                && (searchText.isEmpty
                    || entry.title?.localizedCaseInsensitiveContains(searchText) == true
                    || entry.note?.localizedCaseInsensitiveContains(searchText) == true
                    || entry.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
                    || tripName(for: entry)?.localizedCaseInsensitiveContains(searchText) == true)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(filteredEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title?.isEmpty == false ? entry.title! : entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        Text(String(format: "%.5f, %.5f", entry.latitude, entry.longitude))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !entry.tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(entry.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.tagColor(for: tag).opacity(0.22))
                                        .foregroundStyle(AppTheme.tagTextColor(for: tag))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if dropTargetID == entry.id {
                            RoundedRectangle(cornerRadius: 6).strokeBorder(AppTheme.cobalt, lineWidth: 2)
                        }
                    }
                    .onDrop(of: MacSpotDrop.acceptedTypes, isTargeted: Binding(
                        get: { dropTargetID == entry.id },
                        set: { dropTargetID = $0 ? entry.id : (dropTargetID == entry.id ? nil : dropTargetID) }
                    )) { providers in
                        handleDrop(providers, onto: entry)
                        return true
                    }
                    .tag(entry.id)
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                spotActions(for: filteredEntries.filter { ids.contains($0.id) })
            }
            .onDeleteCommand {
                delete(selectedEntries)
            }
            .onPasteCommand(of: MacSpotDrop.acceptedTypes) { providers in
                handleDrop(providers, onto: selectedEntries.count == 1 ? selectedEntries.first : nil)
            }
            .onDrop(of: MacSpotDrop.acceptedTypes, isTargeted: nil) { providers in
                handleDrop(providers, onto: nil)
                return true
            }
            .overlay(alignment: .bottom) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .searchable(text: $searchText, prompt: "Search spots, notes, tags")
            .navigationTitle("Photo Point")
            .toolbar {
                ToolbarItem {
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
                ToolbarItem {
                    Button {
                        showingTrips = true
                    } label: {
                        Label("Manage Trips", systemImage: "signpost.right.and.left")
                    }
                }
                ToolbarItem {
                    Button(action: openTripPlanner) {
                        Label("Plan Trip Day", systemImage: "calendar.badge.clock")
                    }
                    .disabled(trips.isEmpty)
                    .help("Order a trip's stops, see best light and drive times for a date, and print a shot sheet")
                }
                ToolbarItem {
                    Button {
                        showingAddLocation = true
                    } label: {
                        Label("Add Location", systemImage: "plus.circle")
                    }
                }
                ToolbarItem {
                    Menu {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import from File", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            showingImportHelp = true
                        } label: {
                            Label("Import via AI Chat", systemImage: "sparkles")
                        }
                        if let tripFilter {
                            Divider()
                            Button {
                                findMoreTrip = tripFilter
                            } label: {
                                Label("Find More Near \(tripFilter.name)…", systemImage: "scope")
                            }
                        }
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
                if !selection.isEmpty {
                    ToolbarItem {
                        Button {
                            selection.removeAll()
                        } label: {
                            Label("Show Map", systemImage: "map")
                        }
                    }
                }
            }
        } detail: {
            if selectedEntries.count == 1, let entry = selectedEntries.first {
                EntryDetailView(entry: entry, onClose: { selection.removeAll() })
                    .onDrop(of: MacSpotDrop.acceptedTypes, isTargeted: nil) { providers in
                        handleDrop(providers, onto: entry)
                        return true
                    }
            } else if selectedEntries.count > 1 {
                multiSelectionSummary
            } else {
                MapView(focusRequest: $mapFocus)
            }
        }
        .tint(AppTheme.cobalt)
        // Menu-bar commands (File → New Spot, Trips → Plan Trip Day, …) act on the
        // frontmost main window through this — see MacCommands.
        .focusedSceneValue(\.macCommandActions, MacCommandActions(
            addLocation: { showingAddLocation = true },
            importFromFile: { showingImporter = true },
            importViaAI: { showingImportHelp = true },
            manageTrips: { showingTrips = true },
            planTripDay: trips.isEmpty ? nil : openTripPlanner,
            gearLibrary: { showingGearLibrary = true }
        ))
        .sheet(isPresented: $showingTrips) {
            TripsView()
        }
        .sheet(isPresented: $showingAddLocation) {
            AddLocationView()
        }
        .sheet(isPresented: $showingImportHelp) {
            ImportHelpView()
        }
        .sheet(item: $findMoreTrip) { trip in
            ImportHelpView(trip: trip)
        }
        .sheet(isPresented: $showingGearLibrary) {
            GearLibraryView()
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            Task { await handleImport(result) }
        }
        .alert("Import", isPresented: Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })) {
            Button("OK") { importSummary = nil }
        } message: {
            Text(importSummary ?? "")
        }
    }

    /// Shared by the right-click menu and the multi-selection panel, so both offer the
    /// same actions as the iPhone list's context menu + edit-mode toolbar. Right-clicking
    /// an unselected row acts on just that row; right-clicking inside a selection acts
    /// on the whole selection (standard macOS List behavior).
    @ViewBuilder
    private func spotActions(for targets: [LocationEntryModel]) -> some View {
        if !targets.isEmpty {
            Button {
                showOnMap(targets)
            } label: {
                Label("Show on Map", systemImage: "scope")
            }
            Divider()
        }
        if targets.count == 1, let entry = targets.first {
            Button {
                openInMaps(entry)
            } label: {
                Label("Directions", systemImage: "map")
            }
            Button {
                copyToClipboard(String(format: "%.5f, %.5f", entry.latitude, entry.longitude))
            } label: {
                Label("Copy Coordinates", systemImage: "doc.on.doc")
            }
        }
        if targets.count >= 2, let routeURL = routeURL(for: targets) {
            Link(destination: routeURL) {
                Label("Open Route in Google Maps", systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up")
            }
        }
        if !targets.isEmpty {
            Menu {
                Button("No Trip") { move(targets, toTripID: nil) }
                ForEach(trips) { trip in
                    Button(trip.name) { move(targets, toTripID: trip.id) }
                }
            } label: {
                Label("Move to Trip", systemImage: "signpost.right.and.left")
            }
            Divider()
            if let jsonURL = SpotImportService.exportJSON(targets, name: exportName(for: targets)) {
                ShareLink(item: jsonURL) {
                    Label("Share with Photo Point User", systemImage: "person.badge.plus")
                }
            }
            if let kmlURL = KMLExportService.export(targets, name: exportName(for: targets)) {
                ShareLink(item: kmlURL) {
                    Label("Export KML", systemImage: "square.and.arrow.up")
                }
            }
            Divider()
            Button(role: .destructive) {
                delete(targets)
            } label: {
                Label(targets.count == 1 ? "Delete" : "Delete \(targets.count) Spots", systemImage: "trash")
            }
        }
    }

    private var multiSelectionSummary: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.cobalt)
            Text("\(selectedEntries.count) Spots Selected")
                .font(.title2.weight(.semibold))
            Text("Right-click the selection for more, or use the actions below.")
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    showOnMap(selectedEntries)
                } label: {
                    Label("Show on Map", systemImage: "scope")
                }
                if let routeURL = routeURL(for: selectedEntries) {
                    Link(destination: routeURL) {
                        Label("Open Route", systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Menu {
                    Button("No Trip") { move(selectedEntries, toTripID: nil) }
                    ForEach(trips) { trip in
                        Button(trip.name) { move(selectedEntries, toTripID: trip.id) }
                    }
                } label: {
                    Label("Move to Trip", systemImage: "signpost.right.and.left")
                }
                .fixedSize()
                if let kmlURL = KMLExportService.export(selectedEntries, name: exportName(for: selectedEntries)) {
                    ShareLink(item: kmlURL) {
                        Label("Export KML", systemImage: "square.and.arrow.up")
                    }
                }
                Button(role: .destructive) {
                    delete(selectedEntries)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Stop order follows the sidebar's current order, same as the iPhone's Open Route.
    private func routeURL(for targets: [LocationEntryModel]) -> URL? {
        guard targets.count >= 2 else { return nil }
        return ExternalNavigationService.googleMapsRouteURL(stops: targets.map { (latitude: $0.latitude, longitude: $0.longitude) })
    }

    private func exportName(for targets: [LocationEntryModel]) -> String {
        if targets.count == 1, let title = targets.first?.title, !title.isEmpty { return title }
        return "Photo Point Spots"
    }

    /// Opens on the trip currently filtered to (or the selected spot's trip), if any;
    /// the planner has its own trip picker either way.
    private func openTripPlanner() {
        if let tripID = tripFilter?.id ?? selectedEntries.first?.tripID ?? trips.first?.id {
            openWindow(id: TripPlannerView.windowID, value: tripID)
        }
    }

    /// Swaps the detail pane back to the map (clearing the selection) and flies it to
    /// the spots — the map picks the request up on appear.
    private func showOnMap(_ targets: [LocationEntryModel]) {
        selection.removeAll()
        mapFocus = MapFocusRequest(entryIDs: targets.map(\.id))
    }

    private func move(_ targets: [LocationEntryModel], toTripID tripID: UUID?) {
        for entry in targets {
            entry.tripID = tripID
        }
    }

    private func delete(_ targets: [LocationEntryModel]) {
        for entry in targets {
            selection.remove(entry.id)
            modelContext.delete(entry)
        }
    }

    private func openInMaps(_ entry: LocationEntryModel) {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = entry.title?.isEmpty == false ? entry.title! : "Photo Point Spot"
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    /// A photo dropped/pasted onto a spot attaches to it; with no target spot there's
    /// nowhere to put a bare photo (the map is the place to drop those — it knows the
    /// coordinate). A Google Maps link always becomes a new spot, selected on arrival.
    private func handleDrop(_ providers: [NSItemProvider], onto entry: LocationEntryModel?) {
        Task { @MainActor in
            switch await MacSpotDrop.load(from: providers) {
            case .image(let data):
                if let entry {
                    MacSpotDrop.attachPhoto(data, to: entry, in: modelContext)
                    showStatus("Added photo to \(entry.title?.isEmpty == false ? entry.title! : "spot")")
                } else {
                    showStatus("Drop photos onto a spot, or onto the map to start a new one")
                }
            case .mapsLink(let link):
                showStatus("Looking up that link…")
                if let newEntry = await MacSpotDrop.createSpot(fromMapsLink: link, in: modelContext) {
                    selection = [newEntry.id]
                    showStatus("Added \(newEntry.title ?? "spot") from Google Maps")
                } else {
                    showStatus("Couldn't find a location in that link")
                }
            case nil:
                break
            }
        }
    }

    private func showStatus(_ message: String) {
        withAnimation { statusMessage = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if statusMessage == message {
                withAnimation { statusMessage = nil }
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) async {
        guard let url = try? result.get() else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importSummary = "Couldn't read that file."
            return
        }
        importSummary = await SpotImportService.importSpots(from: data, into: modelContext)
    }
}

#Preview {
    MacContentView()
        .modelContainer(for: [LocationEntryModel.self, TripModel.self], inMemory: true)
}
