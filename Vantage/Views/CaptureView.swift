import SwiftData
import SwiftUI

struct CaptureView: View {
    @StateObject private var captureService = LocationCaptureService()
    @Query(sort: \LocationEntryModel.timestamp, order: .reverse) private var entries: [LocationEntryModel]
    @Query(sort: \TripModel.createdDate, order: .reverse) private var trips: [TripModel]
    @AppStorage(ActiveTripStore.key) private var activeTripIDString: String = ""
    @State private var selectedEntry: LocationEntryModel?
    @State private var showingTrips = false

    private var activeTrip: TripModel? {
        trips.first { $0.id.uuidString == activeTripIDString }
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
                } else {
                    List(entries) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            VStack(alignment: .leading) {
                                Text(entry.title?.isEmpty == false ? entry.title! : entry.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.headline)
                                Text(String(format: "%.5f, %.5f", entry.latitude, entry.longitude))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    if entry.title?.isEmpty == false {
                                        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                    }
                                    if let heading = entry.headingDegrees {
                                        Text(String(format: "Heading %.0f°", heading))
                                    }
                                    if !entry.photoReferences.isEmpty {
                                        Label("\(entry.photoReferences.count)", systemImage: "photo")
                                    }
                                    if entry.note != nil {
                                        Image(systemName: "note.text")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Vantage")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(AppTheme.cobalt)
        .onAppear { captureService.requestPermissionIfNeeded() }
        .sheet(item: $selectedEntry) { entry in
            EntryDetailView(entry: entry)
        }
        .sheet(isPresented: $showingTrips) {
            TripsView()
        }
    }

    private func capture() {
        Task {
            await CaptureAndSaveUseCase.run(using: captureService)
        }
    }
}

#Preview {
    CaptureView()
        .modelContainer(for: [LocationEntryModel.self, TripModel.self], inMemory: true)
}
