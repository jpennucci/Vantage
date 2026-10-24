import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CaptureView: View {
    @StateObject private var captureService = LocationCaptureService()
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocationEntryModel.timestamp, order: .reverse) private var entries: [LocationEntryModel]
    @Query(sort: \TripModel.createdDate, order: .reverse) private var trips: [TripModel]
    @AppStorage(ActiveTripStore.key) private var activeTripIDString: String = ""
    @State private var selectedEntry: LocationEntryModel?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingTrips = false
    @State private var showingAddLocation = false
    @State private var showingImporter = false
    @State private var showingImportHelp = false
    @State private var screenshotTrip: TripModel?
    @State private var showingScreenshotWizard = false
    @State private var importSummary: String?
    @State private var showingSavedToast = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedEntryIDs = Set<UUID>()
    @State private var tagFilter: String?
    @State private var tripFilter: TripModel?
    @State private var searchText = ""
    @State private var nearMeLocation: CLLocation?
    @State private var isLocatingForSort = false
    @Environment(\.openURL) private var openURL

    private var activeTrip: TripModel? {
        trips.first { $0.id.uuidString == activeTripIDString }
    }

    private var allTags: [String] {
        Array(Set(entries.flatMap(\.tags))).sorted()
    }

    private func tripName(for entry: LocationEntryModel) -> String? {
        guard let tripID = entry.tripID else { return nil }
        return trips.first { $0.id == tripID }?.name
    }

    private func matchesSearch(_ entry: LocationEntryModel) -> Bool {
        guard !searchText.isEmpty else { return true }
        let query = searchText.lowercased()
        if let title = entry.title, title.lowercased().contains(query) { return true }
        if let note = entry.note, note.lowercased().contains(query) { return true }
        if let parkingNotes = entry.parkingNotes, parkingNotes.lowercased().contains(query) { return true }
        if entry.tags.contains(where: { $0.lowercased().contains(query) }) { return true }
        if let tripName = tripName(for: entry), tripName.lowercased().contains(query) { return true }
        return false
    }

    private func distance(to entry: LocationEntryModel) -> CLLocationDistance? {
        guard let nearMeLocation else { return nil }
        return CLLocation(latitude: entry.latitude, longitude: entry.longitude).distance(from: nearMeLocation)
    }

    private var filteredEntries: [LocationEntryModel] {
        let base = entries.filter { entry in
            (tagFilter == nil || entry.tags.contains(tagFilter!))
                && (tripFilter == nil || entry.tripID == tripFilter!.id)
                && matchesSearch(entry)
        }
        guard nearMeLocation != nil else { return base }
        return base.sorted { (distance(to: $0) ?? .greatestFiniteMagnitude) < (distance(to: $1) ?? .greatestFiniteMagnitude) }
    }

    private func toggleNearMe() {
        if nearMeLocation != nil {
            nearMeLocation = nil
            return
        }
        Task {
            isLocatingForSort = true
            nearMeLocation = await captureService.currentCoordinate()
            isLocatingForSort = false
        }
    }

    /// Room for the list and a spot side by side (an unfolded iPhone Duo, an iPad):
    /// the selected spot opens in a pane beside the list instead of a sheet.
    private var showsDetailPane: Bool { horizontalSizeClass == .regular }

    var body: some View {
        FoldSplitLayout(showsSecondary: showsDetailPane) {
            listStack
        } secondary: {
            if let entry = selectedEntry {
                EntryDetailView(entry: entry, onClose: { selectedEntry = nil })
                    .id(entry.id)
            } else {
                ContentUnavailableView(
                    "No Spot Selected",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Pick a spot from the list to see it here.")
                )
            }
        }
    }

    private var listStack: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Button(action: capture) {
                    Label("Save This Spot", systemImage: "mappin.circle.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [AppTheme.cobalt, AppTheme.cobaltLight], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(captureService.isCapturing)
                .padding(.horizontal)
                .padding(.top, 8)

                Button {
                    showingTrips = true
                } label: {
                    Label(activeTrip?.name ?? "No Active Trip", systemImage: "signpost.right.and.left")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.cobaltLight)

                if let error = captureService.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Spots Yet",
                        systemImage: "mappin.slash",
                        description: Text("Tap Save This Spot to log your first location.")
                    )
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No spots match the current filter.")
                    )
                } else {
                    List(filteredEntries, selection: $selectedEntryIDs) { entry in
                        Group {
                            if editMode.isEditing {
                                entryRow(entry, distance: distance(to: entry))
                            } else {
                                Button {
                                    selectedEntry = entry
                                } label: {
                                    entryRow(entry, distance: distance(to: entry))
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                        .listRowBackground(showsDetailPane && selectedEntry?.id == entry.id ? AppTheme.cobalt.opacity(0.25) : nil)
                        .contextMenu {
                            Button {
                                withAnimation { editMode = .active }
                                selectedEntryIDs = [entry.id]
                            } label: {
                                Label("Select Multiple", systemImage: "checkmark.circle")
                            }
                            Button {
                                openInMaps(entry)
                            } label: {
                                Label("Directions", systemImage: "map")
                            }
                            if let wazeURL = ExternalNavigationService.wazeURL(latitude: entry.latitude, longitude: entry.longitude) {
                                Button {
                                    openURL(wazeURL)
                                } label: {
                                    Label("Open in Waze", systemImage: "location.north.circle")
                                }
                            }
                            Button {
                                copyToClipboard(String(format: "%.5f, %.5f", entry.latitude, entry.longitude))
                            } label: {
                                Label("Copy Coordinates", systemImage: "doc.on.doc")
                            }
                            Menu {
                                if entry.tripID != nil {
                                    Button("No Trip") { entry.tripID = nil }
                                }
                                ForEach(trips) { trip in
                                    if trip.id != entry.tripID {
                                        Button(trip.name) { entry.tripID = trip.id }
                                    }
                                }
                            } label: {
                                Label("Move to Trip", systemImage: "signpost.right.and.left")
                            }
                            if let kmlURL = KMLExportService.export([entry], name: entry.title?.isEmpty == false ? entry.title! : "Photo Point Spot") {
                                ShareLink(item: kmlURL) {
                                    Label("Export KML", systemImage: "square.and.arrow.up")
                                }
                            }
                            Button(role: .destructive) {
                                modelContext.delete(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                openInMaps(entry)
                            } label: {
                                Label("Directions", systemImage: "map")
                            }
                            .tint(AppTheme.cobalt)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .tag(entry.id)
                    }
                    .environment(\.editMode, $editMode)
                    .searchable(text: $searchText, prompt: "Search spots, notes, tags")
                }
            }
            .navigationTitle(ScreenshotSeedData.isScreenshotMode ? "" : "Photo Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !editMode.isEditing {
                    ToolbarItem(placement: .topBarLeading) {
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
                            Divider()
                            Toggle(isOn: Binding(get: { nearMeLocation != nil }, set: { _ in toggleNearMe() })) {
                                Label("Nearest First", systemImage: "location")
                            }
                            .disabled(captureService.isCapturing)
                        } label: {
                            if isLocatingForSort {
                                ProgressView()
                            } else {
                                Label("Filter", systemImage: (tagFilter != nil || tripFilter != nil || nearMeLocation != nil) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            }
                        }
                    }
                    // One menu with words in it, rather than three bare icons (the import
                    // tray in particular read as "download").
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showingAddLocation = true
                            } label: {
                                Label("Add Location", systemImage: "mappin.and.ellipse")
                            }
                            Divider()
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
                        } label: {
                            Label("Add", systemImage: "plus.circle")
                        }
                    }
                }
                if editMode.isEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            withAnimation {
                                editMode = .inactive
                                selectedEntryIDs.removeAll()
                            }
                        }
                    }
                    if let routeURL = selectedEntriesRouteURL {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                openURL(routeURL)
                            } label: {
                                Label("Open Route", systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("No Trip") { moveSelectedEntries(toTripID: nil) }
                            ForEach(trips) { trip in
                                Button(trip.name) { moveSelectedEntries(toTripID: trip.id) }
                            }
                        } label: {
                            Label("Move to Trip", systemImage: "signpost.right.and.left")
                        }
                        .disabled(selectedEntryIDs.isEmpty)
                    }
                    if let jsonURL = selectedEntriesJSONURL {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: jsonURL) {
                                Label("Share with Photo Point User", systemImage: "person.badge.plus")
                            }
                        }
                    }
                    if let kmlURL = selectedEntriesKMLURL {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: kmlURL) {
                                Label("Export KML", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            for entry in entries where selectedEntryIDs.contains(entry.id) {
                                modelContext.delete(entry)
                            }
                            withAnimation {
                                editMode = .inactive
                                selectedEntryIDs.removeAll()
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(selectedEntryIDs.isEmpty)
                    }
                }
            }
        }
        .tint(AppTheme.cobalt)
        .onAppear {
            if ScreenshotSeedData.isScreenshotMode {
                let screen = ProcessInfo.processInfo.environment["VANTAGE_SCREENSHOT_SCREEN"]
                if screen == "detail" {
                    selectedEntry = entries.first
                } else if screen == "trips" {
                    showingTrips = true
                } else if screen == "import" {
                    showingImportHelp = true
                } else if screen == "wizard" {
                    showingScreenshotWizard = true
                } else if screen?.hasPrefix("trip-") == true || screen == "finds-trip" {
                    Task { screenshotTrip = await ScreenshotScreen.demoTrip(in: modelContext) }
                }
            } else {
                captureService.requestPermissionIfNeeded()
            }
        }
        // In the split layout the spot opens in the pane instead. Unfolding with
        // this sheet up moves the spot into the pane; folding moves it back.
        .sheet(item: showsDetailPane ? .constant(nil) : $selectedEntry) { entry in
            EntryDetailView(entry: entry)
        }
        .sheet(isPresented: $showingTrips) {
            TripsView()
        }
        .sheet(isPresented: $showingAddLocation) {
            AddLocationView()
        }
        .sheet(isPresented: $showingImportHelp) {
            ImportHelpView()
        }
        .sheet(item: $screenshotTrip) { trip in
            NavigationStack {
                TripDetailView(trip: trip, initialTab: ScreenshotScreen.is("trip-route") || ScreenshotScreen.is("finds-trip") ? .route : ScreenshotScreen.is("trip-packing") ? .packing : .itinerary)
            }
        }
        .sheet(isPresented: $showingScreenshotWizard) {
            TripWizardView { _, _ in }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            Task { await handleImport(result) }
        }
        .alert("Import", isPresented: Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })) {
            Button("OK") { importSummary = nil }
        } message: {
            Text(importSummary ?? "")
        }
        .overlay(alignment: .top) {
            if showingSavedToast {
                Label("Spot Saved", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppTheme.cobalt, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vantageEntrySaved)) { _ in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { showingSavedToast = true }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation { showingSavedToast = false }
            }
        }
    }

    private func capture() {
        Task {
            await CaptureAndSaveUseCase.run(using: captureService)
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

    private var selectedEntriesKMLURL: URL? {
        guard !selectedEntryIDs.isEmpty else { return nil }
        let selected = entries.filter { selectedEntryIDs.contains($0.id) }
        return KMLExportService.export(selected, name: "Photo Point Spots")
    }

    private var selectedEntriesJSONURL: URL? {
        guard !selectedEntryIDs.isEmpty else { return nil }
        let selected = entries.filter { selectedEntryIDs.contains($0.id) }
        return SpotImportService.exportJSON(selected, name: "Photo Point Spots")
    }

    /// Stop order follows the list's current sort (timestamp, or distance when "Near
    /// Me" is active) — whatever order the entries are already showing in.
    private var selectedEntriesRouteURL: URL? {
        guard selectedEntryIDs.count >= 2 else { return nil }
        let stops = filteredEntries
            .filter { selectedEntryIDs.contains($0.id) }
            .map { (latitude: $0.latitude, longitude: $0.longitude) }
        return ExternalNavigationService.googleMapsRouteURL(stops: stops)
    }

    private func moveSelectedEntries(toTripID tripID: UUID?) {
        for entry in entries where selectedEntryIDs.contains(entry.id) {
            entry.tripID = tripID
        }
        withAnimation {
            editMode = .inactive
            selectedEntryIDs.removeAll()
        }
    }

    private func openInMaps(_ entry: LocationEntryModel) {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = entry.title?.isEmpty == false ? entry.title! : "Photo Point Spot"
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func entryRow(_ entry: LocationEntryModel, distance: CLLocationDistance? = nil) -> some View {
        SpotListRow(entry: entry, distance: distance)
    }
}

/// A spot in the Capture list: name, where it is, its best light, and its tags.
/// Everything wraps rather than scrolling sideways, so nothing is cut off at large
/// text sizes; coordinates and heading live on the detail screen.
private struct SpotListRow: View {
    let entry: LocationEntryModel
    let distance: CLLocationDistance?
    @State private var placeName: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(entry: LocationEntryModel, distance: CLLocationDistance?) {
        self.entry = entry
        self.distance = distance
        _placeName = State(initialValue: PlaceNameService.shared.cachedName(latitude: entry.latitude, longitude: entry.longitude))
    }

    private var hasTitle: Bool { entry.title?.isEmpty == false }

    var body: some View {
        // At accessibility sizes the photo goes above the text, which then gets the
        // full width instead of wrapping a word per line beside it.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            if dynamicTypeSize.isAccessibilitySize {
                EntryThumbnailView(entry: entry)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(hasTitle ? entry.title! : entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Text(placeName ?? entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 12) {
                    if let suggestion = entry.goldenHourSuggestion {
                        Text("Best light \(suggestion.time.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(AppTheme.apertureGold)
                    }
                    if let distance {
                        Text(Measurement(value: distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
                            .foregroundStyle(AppTheme.cobaltLight)
                    }
                    if let photoCount = entry.photos?.count, photoCount > 0 {
                        Label("\(photoCount)", systemImage: "photo")
                            .accessibilityLabel("\(photoCount) photo\(photoCount == 1 ? "" : "s")")
                    }
                    if entry.note != nil {
                        Image(systemName: "note.text")
                            .accessibilityLabel("Has notes")
                    }
                    if entry.parkingNotes != nil {
                        Image(systemName: "parkingsign.circle")
                            .accessibilityLabel("Has parking notes")
                    }
                    if !entry.shotList.isEmpty {
                        let doneCount = entry.shotList.filter(\.isDone).count
                        Label("\(doneCount)/\(entry.shotList.count)", systemImage: "checklist")
                            .accessibilityLabel("\(doneCount) of \(entry.shotList.count) shots done")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                // FlowLayout measures each item unconstrained, which collapses Labels
                // to their icon; keep the counts visible.
                .labelStyle(.titleAndIcon)

                if !entry.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(entry.tags, id: \.self) { tag in
                            TagChip(tag: tag, isAutoTag: entry.autoTags.contains(tag))
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize {
                EntryThumbnailView(entry: entry)
            }
        }
        // One stop for VoiceOver: "Montauk Point Overlook, Montauk, NY, Best light 5:54 PM…"
        .accessibilityElement(children: .combine)
        .task(id: entry.id) {
            if placeName == nil {
                placeName = await PlaceNameService.shared.name(latitude: entry.latitude, longitude: entry.longitude)
            }
        }
    }
}

/// A tag chip. Orange tags were applied automatically, pink ones typed by hand — the
/// color says it at a glance, the VoiceOver label says it out loud.
struct TagChip: View {
    let tag: String
    let isAutoTag: Bool

    var body: some View {
        let color = AppTheme.tagColor(for: tag, isAutoTag: isAutoTag)
        Text(tag)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.22))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel(isAutoTag ? "\(tag), automatic tag" : "\(tag) tag")
    }
}

private struct EntryThumbnailView: View {
    let entry: LocationEntryModel

    var body: some View {
        if let data = entry.photos?.first?.imageData, let photo = loadPhoto(from: data) {
            photo
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

#Preview {
    CaptureView()
        .modelContainer(for: [LocationEntryModel.self, TripModel.self], inMemory: true)
}
