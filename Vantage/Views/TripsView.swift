import SwiftData
import SwiftUI

struct TripsView: View {
    @Query(sort: \TripModel.createdDate, order: .reverse) private var trips: [TripModel]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ActiveTripStore.key) private var activeTripIDString: String = ""
    @State private var newTripName = ""

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
                        tripRow(name: "No Active Trip", isActive: activeTripIDString.isEmpty)
                    }
                    .foregroundStyle(.primary)

                    ForEach(trips) { trip in
                        Button {
                            activeTripIDString = trip.id.uuidString
                        } label: {
                            tripRow(name: trip.name, isActive: activeTripIDString == trip.id.uuidString)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete(perform: deleteTrips)
                }
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.cobalt)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func tripRow(name: String, isActive: Bool) -> some View {
        HStack {
            Text(name)
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
            let trip = trips[index]
            if trip.id.uuidString == activeTripIDString {
                activeTripIDString = ""
            }
            modelContext.delete(trip)
        }
    }
}
