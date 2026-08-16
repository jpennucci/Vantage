import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Bindable var entry: LocationEntryModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingCamera = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(entry.photoReferences, id: \.self) { url in
                                if let uiImage = UIImage(contentsOfFile: url.path) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Add Photo", systemImage: "camera")
                    }
                }

                Section("Note") {
                    // Tapping the microphone on the system keyboard dictates directly
                    // into this field — no separate voice-recording pipeline needed.
                    TextEditor(text: Binding(
                        get: { entry.note ?? "" },
                        set: { entry.note = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 120)
                }

                Section("Location") {
                    Text(String(format: "%.5f, %.5f", entry.latitude, entry.longitude))
                    if let heading = entry.headingDegrees {
                        Text(String(format: "Heading %.0f°", heading))
                    }
                    Text(entry.timestamp, style: .date) + Text(" at ") + Text(entry.timestamp, style: .time)
                }
            }
            .navigationTitle("Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView { image in
                    if let url = PhotoStorageService.save(image) {
                        entry.photoReferences.append(url)
                        try? modelContext.save()
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
}
