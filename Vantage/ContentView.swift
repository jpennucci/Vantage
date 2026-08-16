import SwiftData
import SwiftUI

struct ContentView: View {
    @StateObject private var captureService = LocationCaptureService()
    @Query(sort: \LocationEntryModel.timestamp, order: .reverse) private var entries: [LocationEntryModel]
    @State private var selectedEntry: LocationEntryModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Button(action: capture) {
                    Label("Save This Spot", systemImage: "mappin.circle.fill")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(captureService.isCapturing)
                .padding(.horizontal)

                if let error = captureService.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

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
            .navigationTitle("Vantage")
        }
        .onAppear { captureService.requestPermissionIfNeeded() }
        .sheet(item: $selectedEntry) { entry in
            EntryDetailView(entry: entry)
        }
    }

    private func capture() {
        Task {
            await CaptureAndSaveUseCase.run(using: captureService)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: LocationEntryModel.self, inMemory: true)
}
