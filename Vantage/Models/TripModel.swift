import Foundation
import SwiftData

@Model
final class TripModel {
    var id: UUID = UUID()
    var name: String = ""
    var createdDate: Date = Date()

    init(id: UUID = UUID(), name: String, createdDate: Date = Date()) {
        self.id = id
        self.name = name
        self.createdDate = createdDate
    }
}
