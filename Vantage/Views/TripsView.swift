import SwiftData
import SwiftUI

struct TripsView: View {
    @Query(sort: \TripModel.createdDate, order: .reverse) private var trips: [TripModel]
    @Query private var entries: [LocationEntryModel]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ActiveTripStore.key) private var activeTripIDString: String = ""
    @State private var newTripName = ""
    @State private var renamingTrip: TripModel?
    @State private var renameText = ""

    private func entryCount(for trip: TripModel) -> Int {
        entries.filter { $0.tripID == trip.id }.count
    }

    private func kmlURL(for trip: TripModel) -> URL? {
        let tripEntries = entries.filter { $0.tripID == trip.id }
        guard !tripEntries.isEmpty else { return nil }
        return KMLExportService.export(tripEntries, name: trip.name)
    }

    private func jsonURL(for trip: TripModel) -> URL? {
        let tripEntries = entries.filter { $0.tripID == trip.id }
        guard !tripEntries.isEmpty else { return nil }
        return SpotImportService.exportJSON(tripEntries, name: trip.name)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New trip name", text: $newTripName)
                        Button("Add", action: addTrip)
                            .disabled(newTripName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Active Trip") {
                    Button {
                        activeTripIDString = ""
                    } label: {
                        tripRow(name: "No Active Trip", count: entries.filter { $0.tripID == nil }.count, isActive: activeTripIDString.isEmpty)
                    }
                    .foregroundStyle(.primary)

                    ForEach(trips) { trip in
                        Button {
                            activeTripIDString = trip.id.uuidString
                        } label: {
                            tripRow(name: trip.name, count: entryCount(for: trip), isActive: activeTripIDString == trip.id.uuidString)
                        }
                        .foregroundStyle(.primary)
                        #if os(iOS)
                        .swipeActions(edge: .leading) {
                            Button {
                                renameText = trip.name
                                renamingTrip = trip
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(AppTheme.cobalt)
                            if let jsonURL = jsonURL(for: trip) {
                                ShareLink(item: jsonURL) {
                                    Label("Share with Vantage User", systemImage: "person.badge.plus")
                                }
                                .tint(AppTheme.customTagBright)
                            }
                            if let kmlURL = kmlURL(for: trip) {
                                ShareLink(item: kmlURL) {
                                    Label("Export KML", systemImage: "square.and.arrow.up")
                                }
                                .tint(AppTheme.shutterGreen)
                            }
                        }
                        #else
                        .contextMenu {
                            Button {
                                renameText = trip.name
                                renamingTrip = trip
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            if let jsonURL = jsonURL(for: trip) {
                                ShareLink(item: jsonURL) {
                                    Label("Share with Vantage User", systemImage: "person.badge.plus")
                                }
                            }
                            if let kmlURL = kmlURL(for: trip) {
                                ShareLink(item: kmlURL) {
                                    Label("Export KML", systemImage: "square.and.arrow.up")
                                }
                            }
                            Button(role: .destructive) {
                                deleteTrip(trip)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        #endif
                    }
                    #if os(iOS)
                    .onDelete(perform: deleteTrips)
                    #endif
                }
            }
            .navigationTitle("Trips")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .tint(AppTheme.cobalt)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Trip", isPresented: Binding(get: { renamingTrip != nil }, set: { if !$0 { renamingTrip = nil } })) {
                TextField("Trip name", text: $renameText)
                Button("Save") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { renamingTrip?.name = trimmed }
                    renamingTrip = nil
                }
                Button("Cancel", role: .cancel) { renamingTrip = nil }
            }
        }
    }

    private func tripRow(name: String, count: Int, isActive: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text("\(count) spot\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.cobaltLight)
            }
        }
    }

    private func addTrip() {
        let name = newTripName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let trip = TripModel(name: name)
        modelContext.insert(trip)
        activeTripIDString = trip.id.uuidString
        newTripName = ""
    }

    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            deleteTrip(trips[index])
        }
    }

    private func deleteTrip(_ trip: TripModel) {
        if trip.id.uuidString == activeTripIDString {
            activeTripIDString = ""
        }
        modelContext.delete(trip)
    }
}
