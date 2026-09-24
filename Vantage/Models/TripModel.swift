import Foundation
import SwiftData

@Model
final class TripModel {
    var id: UUID = UUID()
    var name: String = ""
    var createdDate: Date = Date()
    /// What to bring — see PackingItem. Gear that the trip's stops need (their
    /// `gearNeeded`) is shown alongside it without being copied in.
    var packingList: [PackingItem] = []
    /// JSON-encoded `TripPlan` (days, stop order, start points and times). Encoded
    /// rather than modeled so the itinerary syncs as one unit and its shape can grow
    /// without further CloudKit schema changes. See TripPlanning.swift.
    var planData: Data?
    /// JSON-encoded `TripRoute` — the route finder's setup and progress.
    var routeData: Data?

    init(id: UUID = UUID(), name: String, createdDate: Date = Date()) {
        self.id = id
        self.name = name
        self.createdDate = createdDate
    }
}
