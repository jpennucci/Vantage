import Foundation
import SwiftData

/// One piece of gear or personal item in the user's reusable library — entered once,
/// then added to trips' packing lists individually or as part of a kit ("Landscape
/// kit", "Road trip basics"). Synced so the library is the same on every device.
///
/// Like every model here: defaults on all properties and nothing `.unique`, as
/// SwiftData's CloudKit mirroring requires.
@Model
final class GearItem {
    var id: UUID = UUID()
    var name: String = ""
    /// A `GearCategory` raw value — stored as a string so new categories never need a
    /// schema change.
    var category: String = GearCategory.camera.rawValue
    /// Names of the kits this item belongs to; an item can be in several.
    var kits: [String] = []
    var createdDate: Date = Date()

    init(id: UUID = UUID(), name: String, category: GearCategory = .camera, kits: [String] = [], createdDate: Date = Date()) {
        self.id = id
        self.name = name
        self.category = category.rawValue
        self.kits = kits
        self.createdDate = createdDate
    }

    var gearCategory: GearCategory {
        GearCategory(rawValue: category) ?? .other
    }
}

enum GearCategory: String, CaseIterable, Codable, Identifiable {
    case camera = "Camera"
    case lenses = "Lenses"
    case drone = "Drone"
    case support = "Support"
    case lighting = "Lighting & Filters"
    case power = "Power & Storage"
    case personal = "Personal"
    case clothing = "Clothing"
    case documents = "Documents"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .camera: "camera"
        case .lenses: "camera.aperture"
        case .drone: "airplane"
        case .support: "line.3.crossed.swirl.circle"
        case .lighting: "light.max"
        case .power: "battery.100.bolt"
        case .personal: "bag"
        case .clothing: "tshirt"
        case .documents: "doc.text"
        case .other: "shippingbox"
        }
    }

    /// Equipment you take out at a stop (and so need to remember to put back) — as
    /// opposed to personal items that live in the car or the bag all day.
    var isEquipment: Bool {
        switch self {
        case .camera, .lenses, .drone, .support, .lighting, .power: true
        case .personal, .clothing, .documents, .other: false
        }
    }
}
