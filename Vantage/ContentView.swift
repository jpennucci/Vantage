import SwiftData
import SwiftUI

struct ContentView: View {
    @StateObject private var captureService = LocationCaptureService()
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocationEntryModel.timestamp, order: .reverse) private var entries: [LocationEntryModel]

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
                    VStack(alignment: .leading) {
                        Text(entry.timestamp, style: .time)
                            .font(.headline)
                        Text(String(format: "%.5f, %.5f", entry.latitude, entry.longitude))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let heading = entry.headingDegrees {
                            Text(String(format: "Heading %.0f°", heading))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Vantage")
        }
        .onAppear { captureService.requestPermissionIfNeeded() }
    }

    private func capture() {
        Task {
            if let entry = await captureService.captureLocation() {
                modelContext.insert(entry)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: LocationEntryModel.self, inMemory: true)
}
