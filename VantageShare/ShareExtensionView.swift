import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Wraps `ShareExtensionView` with the same shared, App-Group-backed model container
/// the main app and widget use — see `VantageModelContainer` for why the store has
/// to live there rather than SwiftData's per-process default.
struct ShareExtensionRootView: View {
    let imageData: Data
    let onComplete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ShareExtensionView(imageData: imageData, onComplete: onComplete, onCancel: onCancel)
            .modelContainer(VantageModelContainer.shared)
            .preferredColorScheme(.dark)
    }
}

/// Two ways to use a shared image: attach it to a spot that already exists (the
/// Street View screenshot workflow — you already have the spot open, you're just
/// adding a reference shot to it), or create a brand new spot from a photo picked in
/// the Photos app. Screenshots carry no GPS EXIF, so "create new" primes the pin at
/// the current device location and lets you tap the map to correct it — unlike a
/// real camera photo's location, that's a guess, not a fact.
struct ShareExtensionView: View {
    let imageData: Data
    let onComplete: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocationEntryModel.timestamp, order: .reverse) private var entries: [LocationEntryModel]

    @State private var mode: Mode = .attachExisting
    @State private var searchText = ""
    @State private var isSaving = false

    @State private var newTitle = ""
    @State private var coordinate = CLLocationCoordinate2D()
    @State private var hasLocation = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @StateObject private var captureService = LocationCaptureService()

    private enum Mode: String, CaseIterable {
        case attachExisting = "Add to Existing"
        case createNew = "Create New"
    }

    private var filteredEntries: [LocationEntryModel] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter { ($0.title ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sharedImagePreview
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                switch mode {
                case .attachExisting: existingSpotPicker
                case .createNew: newSpotForm
                }
            }
            .navigationTitle("Photo Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .task { await primeLocation() }
    }

    private var sharedImagePreview: some View {
        Group {
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding([.top, .horizontal], 12)
            }
        }
    }

    private var existingSpotPicker: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView("No Saved Spots Yet", systemImage: "mappin.slash")
            } else {
                List(filteredEntries) { entry in
                    Button {
                        Task { await attach(to: entry) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title?.isEmpty == false ? entry.title! : "Untitled Spot")
                                .font(.body.weight(.medium))
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isSaving)
                }
                .searchable(text: $searchText, prompt: "Search spots")
                .listStyle(.plain)
            }
        }
    }

    private var newSpotForm: some View {
        Form {
            Section {
                TextField("Name (optional)", text: $newTitle)
            }
            Section {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        if hasLocation {
                            Marker(newTitle.isEmpty ? "New Spot" : newTitle, coordinate: coordinate)
                        }
                    }
                    .frame(height: 220)
                    .onTapGesture { point in
                        guard let tapped = proxy.convert(point, from: .local) else { return }
                        coordinate = tapped
                        hasLocation = true
                    }
                }
                Text(hasLocation ? "Tap the map to adjust the pin." : "Locating…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button {
                    Task { await createNewSpot() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Create Spot")
                    }
                }
                .disabled(!hasLocation || isSaving)
            }
        }
    }

    private func primeLocation() async {
        captureService.requestPermissionIfNeeded()
        guard let location = await captureService.currentCoordinate() else { return }
        coordinate = location.coordinate
        hasLocation = true
        cameraPosition = .region(
            MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        )
    }

    private func attach(to entry: LocationEntryModel) async {
        isSaving = true
        let asset = PhotoAsset(imageData: imageData, isReference: true, entry: entry)
        modelContext.insert(asset)
        try? modelContext.save()
        isSaving = false
        onComplete()
    }

    private func createNewSpot() async {
        guard hasLocation else { return }
        isSaving = true
        defer { isSaving = false }

        // tripID intentionally left nil — ActiveTripStore reads UserDefaults.standard,
        // which isn't shared across the App Group, so it can't see the main app's
        // active trip from here (same gap the widget/watch extensions already have).
        let entry = LocationEntryModel(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            title: newTitle.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newTitle
        )
        modelContext.insert(entry)
        let asset = PhotoAsset(imageData: imageData, isReference: true, entry: entry)
        modelContext.insert(asset)
        try? modelContext.save()
        onComplete()
    }
}
