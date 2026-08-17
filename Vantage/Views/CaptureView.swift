import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

struct CaptureView: View {
    @StateObject private var captureService = LocationCaptureService()
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocationEntryModel.timestamp, order: .reverse) private var entries: [LocationEntryModel]
    @Query(sort: \TripModel.createdDate, order: .reverse) private var trips: [TripModel]
    @AppStorage(ActiveTripStore.key) private var activeTripIDString: String = ""
    @State private var selectedEntry: LocationEntryModel?
    @State private var showingTrips = false
    @State private var showingAddLocation = false
    @State private var showingSavedToast = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedEntryIDs = Set<UUID>()
    @State private var tagFilter: String?
    @State private var tripFilter: TripModel?
    @State private var searchText = ""
    @State private var nearMeLocation: CLLocation?
    @State private var isLocatingForSort = false

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

    var body: some View {
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
            .navigationTitle("Vantage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !editMode.isEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("All Tags") { tagFilter = nil }
                            ForEach(allTags, id: \.self) { tag in
                                Button(tag) { tagFilter = tag }
                            }
                        } label: {
                            Label(tagFilter ?? "Tag", systemImage: "tag")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("All Trips") { tripFilter = nil }
                            ForEach(trips) { trip in
                                Button(trip.name) { tripFilter = trip }
                            }
                        } label: {
                            Label(tripFilter?.name ?? "Trip", systemImage: "signpost.right.and.left")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            toggleNearMe()
                        } label: {
                            if isLocatingForSort {
                                ProgressView()
                            } else {
                                Label("Near Me", systemImage: nearMeLocation == nil ? "location" : "location.fill")
                            }
                        }
                        .disabled(captureService.isCapturing)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingAddLocation = true
                        } label: {
                            Label("Add Location", systemImage: "plus.circle")
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
        .onAppear { captureService.requestPermissionIfNeeded() }
        .sheet(item: $selectedEntry) { entry in
            EntryDetailView(entry: entry)
        }
        .sheet(isPresented: $showingTrips) {
            TripsView()
        }
        .sheet(isPresented: $showingAddLocation) {
            AddLocationView()
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

    private var selectedEntriesKMLURL: URL? {
        guard !selectedEntryIDs.isEmpty else { return nil }
        let selected = entries.filter { selectedEntryIDs.contains($0.id) }
        return KMLExportService.export(selected, name: "Vantage Spots")
    }

    private func openInMaps(_ entry: LocationEntryModel) {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = entry.title?.isEmpty == false ? entry.title! : "Vantage Spot"
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func entryRow(_ entry: LocationEntryModel, distance: CLLocationDistance? = nil) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text(entry.title?.isEmpty == false ? entry.title! : entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.headline)
                Text(String(format: "%.5f, %.5f", entry.latitude, entry.longitude))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if let distance {
                        Text(Measurement(value: distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
                            .foregroundStyle(AppTheme.cobaltLight)
                    }
                    if entry.title?.isEmpty == false {
                        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    }
                    if let heading = entry.headingDegrees {
                        Text(String(format: "Heading %.0f°", heading))
                    }
                    if let suggestion = entry.goldenHourSuggestion {
                        Text("Best light \(suggestion.time.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(AppTheme.apertureGold)
                    }
                    if let photoCount = entry.photos?.count, photoCount > 0 {
                        Label("\(photoCount)", systemImage: "photo")
                    }
                    if entry.note != nil {
                        Image(systemName: "note.text")
                    }
                    if entry.parkingNotes != nil {
                        Image(systemName: "parkingsign.circle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !entry.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(entry.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(AppTheme.tagColor(for: tag).opacity(0.22))
                                    .foregroundStyle(AppTheme.tagColor(for: tag))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            EntryThumbnailView(entry: entry)
        }
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
