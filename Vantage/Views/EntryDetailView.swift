import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Bindable var entry: LocationEntryModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingCamera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailSection("Name") {
                        TextField("e.g. Abandoned house", text: Binding(
                            get: { entry.title ?? "" },
                            set: { entry.title = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.subheadline)
                    }

                    detailSection("Photos") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(entry.photoReferences, id: \.self) { url in
                                    if let uiImage = UIImage(contentsOfFile: url.path) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                                Button {
                                    showingCamera = true
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "camera")
                                        Text("Add").font(.caption2)
                                    }
                                    .frame(width: 80, height: 80)
                                    .foregroundStyle(AppTheme.cobaltLight)
                                    .background(AppTheme.moduleBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.moduleBorder, lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }

                    detailSection("Note") {
                        // Tapping the microphone on the system keyboard dictates directly
                        // into this field — no separate voice-recording pipeline needed.
                        TextEditor(text: Binding(
                            get: { entry.note ?? "" },
                            set: { entry.note = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.subheadline)
                        .frame(minHeight: 100)
                    }

                    detailSection("Location") {
                        detailRow("Coordinates", String(format: "%.5f, %.5f", entry.latitude, entry.longitude))
                        if let heading = entry.headingDegrees {
                            detailRow("Heading", String(format: "%.0f°", heading))
                        }
                        detailRow("Captured", entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .tint(AppTheme.cobalt)
            .navigationTitle(entry.title?.isEmpty == false ? entry.title! : "Entry")
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

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }
}
