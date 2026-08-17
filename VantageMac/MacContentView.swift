import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Mac companion — view + light edit of entries synced from the iPhone app (step 15
/// in the build order). No capture flow here: this is a planning/review tool, not
/// a field-capture tool, so there's no "Save This Spot" button.
struct MacContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocationEntryModel.timestamp, order: .reverse) private var entries: [LocationEntryModel]
    @Query(sort: \TripModel.createdDate, order: .reverse) private var trips: [TripModel]
    @State private var selectedEntry: LocationEntryModel?
    @State private var searchText = ""
    @State private var tagFilter: String?
    @State private var tripFilter: TripModel?
    @State private var showingTrips = false
    @State private var showingAddLocation = false
    @State private var showingImporter = false
    @State private var showingImportHelp = false
    @State private var importSummary: String?

    private var allTags: [String] {
        Array(Set(entries.flatMap(\.tags))).sorted()
    }

    private func tripName(for entry: LocationEntryModel) -> String? {
        guard let tripID = entry.tripID else { return nil }
        return trips.first { $0.id == tripID }?.name
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
            List(selection: $selectedEntry) {
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
                    .tag(entry)
                    .contextMenu {
                        Button(role: .destructive) {
                            if selectedEntry == entry { selectedEntry = nil }
                            modelContext.delete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search spots, notes, tags")
            .navigationTitle("Vantage")
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("All Tags") { tagFilter = nil }
                        ForEach(allTags, id: \.self) { tag in
                            Button(tag) { tagFilter = tag }
                        }
                    } label: {
                        Label(tagFilter ?? "Tag", systemImage: "tag")
                    }
                }
                ToolbarItem {
                    Menu {
                        Button("All Trips") { tripFilter = nil }
                        ForEach(trips) { trip in
                            Button(trip.name) { tripFilter = trip }
                        }
                    } label: {
                        Label(tripFilter?.name ?? "Trip", systemImage: "signpost.right.and.left")
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
                    Button {
                        showingAddLocation = true
                    } label: {
                        Label("Add Location", systemImage: "plus.circle")
                    }
                }
                ToolbarItem {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Spots", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem {
                    Button {
                        showingImportHelp = true
                    } label: {
                        Label("How to Import", systemImage: "questionmark.circle")
                    }
                }
                if selectedEntry != nil {
                    ToolbarItem {
                        Button {
                            selectedEntry = nil
                        } label: {
                            Label("Show Map", systemImage: "map")
                        }
                    }
                }
            }
        } detail: {
            if let selectedEntry {
                EntryDetailView(entry: selectedEntry)
            } else {
                MapView()
            }
        }
        .tint(AppTheme.cobalt)
        .sheet(isPresented: $showingTrips) {
            TripsView()
        }
        .sheet(isPresented: $showingAddLocation) {
            AddLocationView()
        }
        .sheet(isPresented: $showingImportHelp) {
            ImportHelpView()
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
