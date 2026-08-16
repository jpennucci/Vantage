import AppIntents

/// Registers "Save this spot" with Siri/Shortcuts — no separate setup needed by the
/// user. Apple requires the app name token in the phrase to avoid collisions with
/// other apps' shortcuts, so the actual spoken phrase is "save this spot in Vantage".
struct VantageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveSpotIntent(),
            phrases: [
                "Save this spot in \(.applicationName)",
                "Save this spot with \(.applicationName)"
            ],
            shortTitle: "Save Spot",
            systemImageName: "mappin.circle.fill"
        )
    }
}
