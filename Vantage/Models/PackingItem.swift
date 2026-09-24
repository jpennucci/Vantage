import Foundation

/// One line on a trip's packing list. A plain Codable struct stored on TripModel (like
/// ShotListItem on an entry) rather than its own model — it's small, belongs to exactly
/// one trip, and a trip's list syncs as a unit.
struct PackingItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// A `GearCategory` raw value.
    var category: String = GearCategory.other.rawValue
    var quantity: Int = 1
    var isPacked: Bool = false

    var gearCategory: GearCategory {
        GearCategory(rawValue: category) ?? .other
    }
}
