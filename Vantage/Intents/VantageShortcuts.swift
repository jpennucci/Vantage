import AppIntents

/// Registers "Save this spot" with Siri/Shortcuts — no separate setup needed by the
/// user. Apple requires the app name token in the phrase to avoid collisions with
/// other apps' shortcuts, so the actual spoken phrase is "save this spot in Vantage".
///
/// `SaveSpotIntent.name` can't be embedded directly in one of these auto-registered
/// phrases — App Shortcuts phrases only allow AppEntity/AppEnum parameters, not
/// freeform String dictation, so a single sentence like "...and call it abandoned
/// house" isn't parseable this way. The name field is still there for editing an
/// entry's title after the fact, and for anyone who wants to wire it up to dictated
/// text manually in the Shortcuts app.
struct VantageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveSpotIntent(),
            phrases: [
                "Save this spot in \(.applicationName)",
                "Save this spot with \(.applicationName)",
                "Save this location in \(.applicationName)",
                "Save this location with \(.applicationName)"
            ],
            shortTitle: "Save Spot",
            systemImageName: "mappin.circle.fill"
        )
    }
}
