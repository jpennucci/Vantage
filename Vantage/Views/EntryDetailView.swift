import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Bindable var entry: LocationEntryModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TripModel.createdDate) private var trips: [TripModel]
    #if os(iOS)
    @State private var showingCamera = false
    #endif
    @State private var newTagText = ""
    @State private var showingDeleteConfirmation = false
    @State private var viewingPhoto: PhotoAsset?
    @State private var newShotText = ""

    private let suggestedTags = ["to shoot", "shot", "needs permission", "seasonal"]

    /// Deliberately generic — works for a stills shot list and a video B-roll list alike.
    private let suggestedShots = ["Wide shot", "Detail shot", "Establishing shot", "B-roll"]

    private var availableSuggestions: [String] {
        suggestedTags.filter { !entry.tags.contains($0) }
    }

    private var availableShotSuggestions: [String] {
        suggestedShots.filter { suggestion in !entry.shotList.contains { $0.text == suggestion } }
    }

    private var tripName: String {
        trips.first { $0.id == entry.tripID }?.name ?? "No Trip"
    }

    /// Oriented roughly the direction the camera was facing when the spot was saved,
    /// since heading is already captured at that moment — no extra input needed.
    private var streetViewURL: URL? {
        var urlString = "https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=\(entry.latitude),\(entry.longitude)"
        if let heading = entry.headingDegrees {
            urlString += "&heading=\(Int(heading))"
        }
        return URL(string: urlString)
    }

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

                    detailSection("Trip") {
                        Menu {
                            Button("No Trip") { entry.tripID = nil }
                            ForEach(trips) { trip in
                                Button(trip.name) { entry.tripID = trip.id }
                            }
                        } label: {
                            HStack {
                                Text(tripName)
                                    .foregroundStyle(entry.tripID == nil ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }

                    detailSection("Tags") {
                        if !entry.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(entry.tags, id: \.self) { tag in
                                        HStack(spacing: 4) {
                                            Text(tag)
                                            Button {
                                                entry.tags.removeAll { $0 == tag }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                            }
                                        }
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(AppTheme.tagColor(for: tag).opacity(0.22))
                                        .foregroundStyle(AppTheme.tagTextColor(for: tag))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        HStack {
                            TextField("Add tag", text: $newTagText)
                                .font(.subheadline)
                                .onSubmit(addNewTag)
                            Button("Add", action: addNewTag)
                                .font(.subheadline)
                                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        if !availableSuggestions.isEmpty {
                            Text("TAP TO ADD")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(availableSuggestions, id: \.self) { tag in
                                        Button {
                                            addTag(tag)
                                        } label: {
                                            Label(tag, systemImage: "plus")
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(AppTheme.tagTextColor(for: tag))
                                        .background(AppTheme.moduleBackground)
                                        .overlay(Capsule().strokeBorder(AppTheme.tagColor(for: tag).opacity(0.5), lineWidth: 1))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    detailSection("Photos") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(entry.photos ?? [], id: \.id) { photoAsset in
                                    if let data = photoAsset.imageData, let photo = loadPhoto(from: data) {
                                        Button {
                                            viewingPhoto = photoAsset
                                        } label: {
                                            photo
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 80, height: 80)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                #if os(iOS)
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
                                #endif
                            }
                        }
                    }

                    detailSection("Shot List") {
                        if !entry.shotList.isEmpty {
                            ForEach($entry.shotList) { $item in
                                HStack(spacing: 10) {
                                    Button {
                                        item.isDone.toggle()
                                    } label: {
                                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.isDone ? AppTheme.shutterGreen : .secondary)
                                    }
                                    .buttonStyle(.plain)

                                    Text(item.text)
                                        .strikethrough(item.isDone)
                                        .foregroundStyle(item.isDone ? .secondary : .primary)

                                    Spacer()

                                    Button {
                                        entry.shotList.removeAll { $0.id == item.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .font(.subheadline)
                            }
                        }

                        HStack {
                            TextField("Add a shot (e.g. wide shot, B-roll)", text: $newShotText)
                                .font(.subheadline)
                                .onSubmit(addNewShot)
                            Button("Add", action: addNewShot)
                                .font(.subheadline)
                                .disabled(newShotText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        if !availableShotSuggestions.isEmpty {
                            Text("TAP TO ADD")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(availableShotSuggestions, id: \.self) { suggestion in
                                        Button {
                                            addShot(suggestion)
                                        } label: {
                                            Label(suggestion, systemImage: "plus")
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(AppTheme.cobaltLight)
                                        .background(AppTheme.moduleBackground)
                                        .overlay(Capsule().strokeBorder(AppTheme.cobaltLight.opacity(0.5), lineWidth: 1))
                                        .clipShape(Capsule())
                                    }
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

                    detailSection("Parking") {
                        TextField("e.g. Pull-off on the shoulder, room for the van", text: Binding(
                            get: { entry.parkingNotes ?? "" },
                            set: { entry.parkingNotes = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                        .font(.subheadline)
                    }

                    detailSection("Location") {
                        detailRow("Coordinates", String(format: "%.5f, %.5f", entry.latitude, entry.longitude))
                        if let heading = entry.headingDegrees {
                            detailRow("Heading", String(format: "%.0f°", heading))
                            if let suggestion = entry.goldenHourSuggestion {
                                detailRow(
                                    "Best Light Today",
                                    suggestion.time.formatted(date: .omitted, time: .shortened)
                                        + String(format: " (±%.0f°)", suggestion.headingDeltaDegrees),
                                    valueColor: AppTheme.apertureGold
                                )
                            }
                        }
                        detailRow("Captured", entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        if let weatherSummary = entry.weatherSummary {
                            detailRow("Weather at Capture", weatherSummary)
                        }
                        if let streetViewURL = streetViewURL {
                            Link(destination: streetViewURL) {
                                detailRow("Street View", "Open ↗", valueColor: AppTheme.linkOrange)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .tint(AppTheme.cobalt)
            .navigationTitle(entry.title?.isEmpty == false ? entry.title! : "Entry")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Delete this spot?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(entry)
                    try? modelContext.save()
                    dismiss()
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView { image in
                    if let data = PhotoStorageService.jpegData(from: image) {
                        let photoAsset = PhotoAsset(imageData: data, entry: entry)
                        modelContext.insert(photoAsset)
                        try? modelContext.save()
                    }
                }
                .ignoresSafeArea()
            }
            #endif
            .sheet(item: $viewingPhoto) { photoAsset in
                PhotoViewerView(photoAsset: photoAsset)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.moduleBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.moduleBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func addNewTag() {
        addTag(newTagText)
        newTagText = ""
    }

    private func addTag(_ tag: String) {
        let value = tag.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !entry.tags.contains(value) else { return }
        entry.tags.append(value)
    }

    private func addNewShot() {
        addShot(newShotText)
        newShotText = ""
    }

    private func addShot(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        entry.shotList.append(ShotListItem(text: value))
    }

    private func detailRow(_ label: String, _ value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
        }
        .font(.subheadline)
    }
}

private struct PhotoViewerView: View {
    let photoAsset: PhotoAsset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let data = photoAsset.imageData, let photo = loadPhoto(from: data) {
                    photo
                        .resizable()
                        .scaledToFit()
                } else {
                    ContentUnavailableView("Photo Unavailable", systemImage: "photo")
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
