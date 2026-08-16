import Foundation

/// The trip new captures get filed under. A plain UserDefaults-backed key rather than
/// a SwiftData relationship, since it's just "which trip is selected right now" —
/// read by CaptureAndSaveUseCase, written by TripsView.
enum ActiveTripStore {
    static let key = "com.jamespennucci.Vantage.activeTripID"

    static var activeTripID: UUID? {
        UserDefaults.standard.string(forKey: key).flatMap(UUID.init)
    }
}
