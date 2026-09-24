import SwiftData
import SwiftUI

/// The reusable gear library: every piece of equipment and personal item, entered
/// once, grouped by category, and optionally part of kits ("Landscape kit") that can be
/// added to a trip's packing list in one go. Synced across devices.
struct GearLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GearItem.name) private var gear: [GearItem]

    @State private var newName = ""
    @State private var newCategory: GearCategory = .camera
    @State private var editing: GearItem?
    @State private var editingKit: KitSelection?
    @State private var showingNewKit = false
    @State private var newKitName = ""

    private var kitNames: [String] {
        Set(gear.flatMap(\.kits)).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Add gear or a personal item", text: $newName)
                            .onSubmit(add)
                        Picker("Category", selection: $newCategory) {
                            ForEach(GearCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Add", action: add)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    if gear.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add your gear once and reuse it on every trip. Group items into kits (like “Landscape kit” or “Road trip basics”) to add them to a packing list in one tap.")
                            Button("Start with a Common Set") { StarterGear.add(to: modelContext) }
                                .buttonStyle(.bordered)
                        }
                        .font(.caption)
                    }
                }

                Section {
                    ForEach(kitNames, id: \.self) { kit in
                        let members = gear.filter { $0.kits.contains(kit) }
                        Button {
                            editingKit = KitSelection(name: kit)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kit).foregroundStyle(.primary)
                                    Text(members.isEmpty ? "No items yet" : members.map(\.name).joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Text("\(members.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        newKitName = ""
                        showingNewKit = true
                    } label: {
                        Label("New Kit", systemImage: "plus")
                    }
                    .disabled(gear.isEmpty)
                } header: {
                    Label("Kits", systemImage: "square.stack.3d.up")
                } footer: {
                    Text("Click a kit to choose its items — an item can be in any number of kits.")
                        .font(.caption)
                }

                ForEach(GearCategory.allCases) { category in
                    let items = gear.filter { $0.gearCategory == category }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { item in
                                Button {
                                    editing = item
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).foregroundStyle(.primary)
                                        if !item.kits.isEmpty {
                                            Text(item.kits.joined(separator: " · "))
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.cobaltLight)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { modelContext.delete(item) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                            .onDelete { offsets in
                                offsets.map { items[$0] }.forEach(modelContext.delete)
                            }
                        } header: {
                            Label(category.rawValue, systemImage: category.symbol)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Gear Library")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { item in
                GearItemEditor(item: item, allKits: kitNames)
            }
            .sheet(item: $editingKit) { kit in
                KitEditor(originalName: kit.name)
            }
            .alert("New Kit", isPresented: $showingNewKit) {
                TextField("Kit name, e.g. Landscape kit", text: $newKitName)
                Button("Next") {
                    let name = newKitName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { editingKit = KitSelection(name: name) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Next, tick the items that belong in it.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        modelContext.insert(GearItem(name: name, category: newCategory))
        newName = ""
    }
}

private struct KitSelection: Identifiable {
    let name: String
    var id: String { name }
}

/// One kit: every item in the library with a checkbox, so a whole kit is built (or
/// changed) in one place instead of item by item. Also renames and deletes the kit —
/// deleting only removes the kit, never the gear.
private struct KitEditor: View {
    let originalName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GearItem.name) private var gear: [GearItem]
    @State private var name = ""
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Kit Name") {
                    TextField("Kit name", text: $name)
                }
                ForEach(GearCategory.allCases) { category in
                    let items = gear.filter { $0.gearCategory == category }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { item in
                                Button {
                                    toggle(item)
                                } label: {
                                    HStack {
                                        Image(systemName: item.kits.contains(originalName) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.kits.contains(originalName) ? AppTheme.cobalt : .secondary)
                                        Text(item.name).foregroundStyle(.primary)
                                        Spacer()
                                        let others = item.kits.filter { $0 != originalName }
                                        if !others.isEmpty {
                                            Text("also in \(others.joined(separator: ", "))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Label(category.rawValue, systemImage: category.symbol)
                        }
                    }
                }
                Section {
                    Button("Delete Kit", role: .destructive) { confirmingDelete = true }
                } footer: {
                    Text("Deleting a kit keeps all its gear in your library.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(originalName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        rename()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete “\(originalName)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Kit", role: .destructive) {
                    for item in gear { item.kits.removeAll { $0 == originalName } }
                    dismiss()
                }
            }
            .onAppear { name = originalName }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    /// Membership is edited under the original name, then renamed once on Done, so
    /// checkmarks stay put while typing a new name.
    private func toggle(_ item: GearItem) {
        if item.kits.contains(originalName) {
            item.kits.removeAll { $0 == originalName }
        } else {
            item.kits.append(originalName)
        }
    }

    private func rename() {
        let newName = name.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != originalName else { return }
        for item in gear where item.kits.contains(originalName) {
            item.kits.removeAll { $0 == originalName }
            if !item.kits.contains(newName) { item.kits.append(newName) }
        }
    }
}

private struct GearItemEditor: View {
    @Bindable var item: GearItem
    let allKits: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var newKit = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $item.name)
                Picker("Category", selection: Binding(
                    get: { item.gearCategory },
                    set: { item.category = $0.rawValue }
                )) {
                    ForEach(GearCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                Section("Kits") {
                    FlowLayout {
                        ForEach(Array(Set(allKits + item.kits)).sorted(), id: \.self) { kit in
                            ChipToggle(title: kit, isOn: Binding(
                                get: { item.kits.contains(kit) },
                                set: { isOn in
                                    if isOn { item.kits.append(kit) } else { item.kits.removeAll { $0 == kit } }
                                }
                            ))
                        }
                    }
                    HStack {
                        TextField("New kit name", text: $newKit)
                            .onSubmit(addKit)
                        Button("Add", action: addKit)
                            .disabled(newKit.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(item.name.isEmpty ? "Gear" : item.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    private func addKit() {
        let kit = newKit.trimmingCharacters(in: .whitespaces)
        guard !kit.isEmpty, !item.kits.contains(kit) else { return }
        item.kits.append(kit)
        newKit = ""
    }
}

/// A sensible first library for a traveling photographer, so the packing list isn't a
/// blank page. Everything is editable/deletable afterward.
enum StarterGear {
    static func add(to context: ModelContext) {
        let landscape = "Landscape kit", drone = "Drone kit", basics = "Road trip basics", night = "Night shooting"
        let items: [(String, GearCategory, [String])] = [
            ("Camera body", .camera, [landscape, night]),
            ("Spare batteries", .power, [landscape, night]),
            ("Memory cards", .power, [landscape, drone, night]),
            ("Wide-angle lens", .lenses, [landscape, night]),
            ("Telephoto lens", .lenses, [landscape]),
            ("Tripod", .support, [landscape, night]),
            ("Remote shutter release", .support, [landscape, night]),
            ("Polarizing filter", .lighting, [landscape]),
            ("ND filters", .lighting, [landscape]),
            ("Lens cloth & blower", .other, [landscape]),
            ("Headlamp (red light)", .lighting, [night]),
            ("Drone", .drone, [drone]),
            ("Drone batteries", .drone, [drone]),
            ("Drone controller", .drone, [drone]),
            ("Laptop & card reader", .power, []),
            ("Chargers & cables", .power, [basics]),
            ("Power bank", .power, [basics]),
            ("Phone charger", .personal, [basics]),
            ("Water", .personal, [basics]),
            ("Snacks", .personal, [basics]),
            ("Sunscreen", .personal, [basics]),
            ("Medications", .personal, [basics]),
            ("Rain jacket", .clothing, [basics]),
            ("Warm layer", .clothing, [basics, night]),
            ("Hiking shoes", .clothing, []),
            ("ID & wallet", .documents, [basics]),
            ("Park pass", .documents, []),
            ("Drone registration / license", .documents, [drone])
        ]
        for (name, category, kits) in items {
            context.insert(GearItem(name: name, category: category, kits: kits))
        }
    }
}
