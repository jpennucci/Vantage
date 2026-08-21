import SwiftData
import SwiftUI
import WatchKit

/// Watch-only capture: independent GPS (no iPhone required, per the spec's
/// stretch-goal note that this is the real advantage over CarPlay/phone-only
/// capture), syncing straight to the same CloudKit container as iPhone/Mac
/// rather than relaying through WatchConnectivity.
struct WatchCaptureView: View {
    @StateObject private var captureService = LocationCaptureService()
    @Query(sort: \LocationEntryModel.timestamp, order: .reverse) private var entries: [LocationEntryModel]
    @State private var lastSavedID: UUID?
    @State private var showingSavedConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Button(action: capture) {
                        if captureService.isCapturing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Save This Spot", systemImage: "mappin.circle.fill")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.cobalt)
                    .disabled(captureService.isCapturing)

                    if showingSavedConfirmation, let lastSavedID {
                        VStack(spacing: 4) {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.shutterGreen)
                            NavigationLink("Add a note", value: lastSavedID)
                                .font(.caption2)
                        }
                        .transition(.opacity)
                    }

                    if let error = captureService.lastError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.warningRed)
                    }

                    if !entries.isEmpty {
                        Divider()
                        Text("Recent")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(entries.prefix(5)) { entry in
                            NavigationLink(value: entry.id) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title?.isEmpty == false ? entry.title! : entry.timestamp.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                    Text(entry.timestamp.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Vantage")
            .navigationDestination(for: UUID.self) { id in
                if let entry = entries.first(where: { $0.id == id }) {
                    WatchEntryNoteView(entry: entry)
                }
            }
            .onAppear { captureService.requestPermissionIfNeeded() }
            // The complication taps into this instead of AppIntent's Button(intent:) —
            // see CaptureWidget.swift for why. widgetURL delivers here on launch.
            .onOpenURL { url in
                guard url.scheme == "vantagewatch", url.host == "capture" else { return }
                capture()
            }
        }
    }

    private func capture() {
        Task {
            showingSavedConfirmation = false
            if let entry = await CaptureAndSaveUseCase.run(using: captureService) {
                lastSavedID = entry.id
                withAnimation { showingSavedConfirmation = true }
                WKInterfaceDevice.current().play(.success)
            } else {
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }
}

/// Tapping the field brings up the Watch's system dictation/Scribble input
/// automatically — same "no separate voice pipeline" pattern as the iPhone note field.
struct WatchEntryNoteView: View {
    @Bindable var entry: LocationEntryModel

    var body: some View {
        Form {
            TextField("Note", text: Binding(
                get: { entry.note ?? "" },
                set: { entry.note = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
        }
        .navigationTitle("Note")
    }
}
