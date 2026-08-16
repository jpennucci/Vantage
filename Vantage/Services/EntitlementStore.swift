import Foundation

/// Single switch gating the paid tier (CloudKit sync, Mac companion app, sharing —
/// see the Free vs. Paid Split in the project spec). Hardcoded unlocked for now:
/// there's no purchase flow and nothing published yet, so nothing to gate in
/// practice. Swapping this for a real StoreKit entitlement check later is a
/// one-line change here, not a retrofit across the app.
enum EntitlementStore {
    static var isPremiumUnlocked: Bool { true }
}
