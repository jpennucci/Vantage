import CoreLocation
import SwiftData
import SwiftUI

/// Manually add a spot without a live GPS capture — for route planning at home:
/// paste a Google Maps link found while researching, type an address, or enter raw
/// coordinates directly. Shared between the Mac app and iOS/iPadOS since none of
/// this depends on platform-specific APIs.
struct AddLocationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var inputMode: InputMode = .mapsLink
    @State private var mapsLinkText = ""
    @State private var addressText = ""
    @State private var latText = ""
    @State private var lngText = ""
    @State private var titleText = ""
    @State private var isResolving = false
    @State private var errorMessage: String?

    private enum InputMode: String, CaseIterable {
        case mapsLink = "Maps Link"
        case address = "Address"
        case coordinates = "Coordinates"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source", selection: $inputMode) {
                        ForEach(InputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("Name (optional)", text: $titleText)

                    switch inputMode {
                    case .mapsLink:
                        TextField("Paste a Google Maps link", text: $mapsLinkText)
                    case .address:
                        TextField("Address", text: $addressText)
                    case .coordinates:
                        TextField("Latitude", text: $latText)
                        TextField("Longitude", text: $lngText)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(AppTheme.warningRed)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Location")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isResolving {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await addLocation() } }
                            .disabled(!canSubmit)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    private var canSubmit: Bool {
        switch inputMode {
        case .mapsLink: return !mapsLinkText.trimmingCharacters(in: .whitespaces).isEmpty
        case .address: return !addressText.trimmingCharacters(in: .whitespaces).isEmpty
        case .coordinates: return !latText.isEmpty && !lngText.isEmpty
        }
    }

    private func addLocation() async {
        errorMessage = nil
        isResolving = true
        defer { isResolving = false }

        var coordinate: (latitude: Double, longitude: Double)?

        switch inputMode {
        case .mapsLink:
            coordinate = await GoogleMapsLinkParser.resolveCoordinates(from: mapsLinkText)
            if coordinate == nil { errorMessage = "Couldn't find coordinates in that link — try pasting the full link, or use Address/Coordinates instead." }
        case .address:
            coordinate = await geocode(address: addressText)
            if coordinate == nil { errorMessage = "Couldn't find that address." }
        case .coordinates:
            if let lat = Double(latText), let lng = Double(lngText) {
                coordinate = (lat, lng)
            } else {
                errorMessage = "Enter valid latitude and longitude."
            }
        }

        guard let coordinate else { return }

        let entry = LocationEntryModel(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            title: titleText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : titleText,
            tripID: ActiveTripStore.activeTripID
        )
        entry.tags.append("planned")
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }

    private func geocode(address: String) async -> (latitude: Double, longitude: Double)? {
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(address)
            guard let location = placemarks.first?.location else { return nil }
            return (location.coordinate.latitude, location.coordinate.longitude)
        } catch {
            return nil
        }
    }
}
