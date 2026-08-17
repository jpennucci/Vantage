import Foundation

/// A single checklist item on an entry — e.g. "wide shot," "detail of barn door,"
/// "B-roll of the road in," "establishing shot at sunset." Deliberately not worded
/// photo-specific, so the same field serves video creators scouting locations too.
/// Plain Codable struct (not a @Model) since it's small text data stored directly on
/// the entry, not something that needs its own CloudKit record like PhotoAsset does.
struct ShotListItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var text: String
    var isDone: Bool = false
}
