import SwiftData
import SwiftUI

/// A trip's packing list: what to bring, grouped by category, checked off while
/// packing (usually on the phone). Items come from the gear library, whole kits, or
/// typed one-offs — and gear that the trip's stops call for is surfaced automatically,
/// with which stops need it, so nothing a planned shot depends on gets left home.
struct PackingListView: View {
    @Bindable var trip: TripModel

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GearItem.name) private var gear: [GearItem]
    @Query private var allEntries: [LocationEntryModel]

    @State private var newItemName = ""
    @State private var newItemCategory: GearCategory = .other
    @State private var showingLibrary = false

    private var tripStops: [LocationEntryModel] {
        allEntries.filter { $0.tripID == trip.id }
    }

    private var kitNames: [String] {
        Set(gear.flatMap(\.kits)).sorted()
    }

    /// Gear name → names of the stops that need it.
    private var neededAtStops: [String: [String]] {
        var result: [String: [String]] = [:]
        for stop in tripStops {
            for item in stop.gearNeeded {
                result[item.lowercased(), default: []].append(stop.title?.isEmpty == false ? stop.title! : "a stop")
            }
        }
        return result
    }

    /// Stop gear that isn't on the list yet.
    private var missingStopGear: [(name: String, stops: [String])] {
        let listed = Set(trip.packingList.map { $0.name.lowercased() })
        var seen = Set<String>()
        var result: [(String, [String])] = []
        for stop in tripStops {
            for item in stop.gearNeeded where !listed.contains(item.lowercased()) && seen.insert(item.lowercased()).inserted {
                result.append((item, neededAtStops[item.lowercased()] ?? []))
            }
        }
        return result
    }

    private var packedCount: Int { trip.packingList.filter(\.isPacked).count }

    var body: some View {
        Form {
            summarySection

            if !missingStopGear.isEmpty {
                Section {
                    ForEach(missingStopGear, id: \.name) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text("Needed at \(item.stops.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") { add(name: item.name, category: category(forGearNamed: item.name)) }
                                .buttonStyle(.bordered)
                        }
                    }
                    Button("Add All") {
                        for item in missingStopGear { add(name: item.name, category: category(forGearNamed: item.name)) }
                    }
                } header: {
                    Label("Your Stops Need", systemImage: "exclamationmark.bubble")
                } footer: {
                    Text("Gear listed on this trip's spots that isn't on the packing list yet.")
                        .font(.caption)
                }
            }

            ForEach(GearCategory.allCases) { category in
                let items = trip.packingList.filter { $0.gearCategory == category }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            row(item)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { items[$0].id }
                            trip.packingList.removeAll { ids.contains($0.id) }
                        }
                    } header: {
                        Label(category.rawValue, systemImage: category.symbol)
                    }
                }
            }

            Section {
                HStack {
                    TextField("Add an item", text: $newItemName)
                        .onSubmit { addTyped() }
                    Picker("Category", selection: $newItemCategory) {
                        ForEach(GearCategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Add") { addTyped() }
                        .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingLibrary) {
            GearLibraryView()
        }
    }

    private var summarySection: some View {
        Section {
            if trip.packingList.isEmpty {
                Text("Nothing on the list yet. Add a kit or items from your gear library below, or type one-off items at the bottom.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(packedCount) of \(trip.packingList.count) packed")
                        .font(.headline)
                    ProgressView(value: Double(packedCount), total: Double(max(trip.packingList.count, 1)))
                        .tint(packedCount == trip.packingList.count ? AppTheme.shutterGreen : AppTheme.cobalt)
                }
            }
            // A scrolling row rather than FlowLayout: Menu labels don't report a usable
            // ideal size to a custom Layout (they collapsed to empty pills on iPhone).
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    if kitNames.isEmpty {
                        Text("No kits yet — create them in the Gear Library")
                    }
                    ForEach(kitNames, id: \.self) { kit in
                        Button(kit) { addKit(kit) }
                    }
                } label: {
                    Label("Add Kit", systemImage: "square.stack.3d.up")
                }
                .fixedSize()
                Menu {
                    ForEach(GearCategory.allCases) { category in
                        let items = gear.filter { $0.gearCategory == category && !isListed($0.name) }
                        if !items.isEmpty {
                            Section(category.rawValue) {
                                ForEach(items) { item in
                                    Button(item.name) { add(name: item.name, category: item.gearCategory) }
                                }
                            }
                        }
                    }
                } label: {
                    Label("Add from Library", systemImage: "plus.rectangle.on.rectangle")
                }
                .fixedSize()
                .disabled(gear.isEmpty)
                Button {
                    showingLibrary = true
                } label: {
                    Label("Gear Library…", systemImage: "books.vertical")
                }
                if packedCount > 0 {
                    Button {
                        for index in trip.packingList.indices { trip.packingList[index].isPacked = false }
                    } label: {
                        Label("Uncheck All", systemImage: "arrow.uturn.backward")
                    }
                    .help("Start over — e.g. to check everything back in for the trip home")
                }
            }
            .fixedSize()
            }
            .buttonStyle(.bordered)
            .menuStyle(.button)
        }
    }

    private func row(_ item: PackingItem) -> some View {
        let index = trip.packingList.firstIndex { $0.id == item.id }
        return HStack {
            Button {
                if let index { trip.packingList[index].isPacked.toggle() }
            } label: {
                Image(systemName: item.isPacked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isPacked ? AppTheme.shutterGreen : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .strikethrough(item.isPacked)
                    .foregroundStyle(item.isPacked ? .secondary : .primary)
                if let stops = neededAtStops[item.name.lowercased()] {
                    Text("Needed at \(stops.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.cobaltLight)
                }
            }
            Spacer()
            if let index {
                Stepper(item.quantity > 1 ? "×\(item.quantity)" : "", value: $trip.packingList[index].quantity, in: 1...99)
                    .fixedSize()
                    .font(.caption.monospacedDigit())
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                trip.packingList.removeAll { $0.id == item.id }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func isListed(_ name: String) -> Bool {
        trip.packingList.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func category(forGearNamed name: String) -> GearCategory {
        gear.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.gearCategory ?? .other
    }

    private func add(name: String, category: GearCategory) {
        guard !isListed(name) else { return }
        trip.packingList.append(PackingItem(name: name, category: category.rawValue))
    }

    private func addKit(_ kit: String) {
        for item in gear where item.kits.contains(kit) {
            add(name: item.name, category: item.gearCategory)
        }
    }

    private func addTyped() {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        add(name: name, category: newItemCategory)
        newItemName = ""
    }
}

/// "Leaving? Check your gear": a quick pass over the equipment you'd have taken out at
/// a stop — what the stop called for plus the trip's packed equipment — before driving
/// off. Deliberately not saved: it's a moment-in-time check, run fresh at every stop.
struct LeaveStopChecklistView: View {
    let entry: LocationEntryModel
    let trip: TripModel?

    @Environment(\.dismiss) private var dismiss
    @State private var checked: Set<String> = []

    private var items: [String] {
        var names = entry.gearNeeded
        for item in trip?.packingList ?? [] where item.gearCategory.isEquipment && item.isPacked {
            if !names.contains(where: { $0.caseInsensitiveCompare(item.name) == .orderedSame }) {
                names.append(item.name)
            }
        }
        return names
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("No gear listed for this stop or packed as equipment for this trip.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items, id: \.self) { name in
                    Button {
                        if checked.contains(name) { checked.remove(name) } else { checked.insert(name) }
                    } label: {
                        Label(name, systemImage: checked.contains(name) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(checked.contains(name) ? AppTheme.shutterGreen : .primary)
                    }
                }
            }
            .navigationTitle("Leaving \(entry.title?.isEmpty == false ? entry.title! : "This Stop")")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(checked.count == items.count && !items.isEmpty ? "All Packed" : "Done") { dismiss() }
                }
            }
        }
    }
}
