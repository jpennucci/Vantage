import SwiftUI

/// Mirrors LumenMeter's AppTheme.swift so the two apps read as a matched toolkit —
/// same palette values, copied by hand for now rather than through a shared package
/// (see the Shared Design System note in the project spec for the longer-term plan).
enum AppTheme {
    static let panelBackground = Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x1B / 255)
    static let moduleBackground = Color(red: 0x1C / 255, green: 0x20 / 255, blue: 0x29 / 255)
    static let moduleBorder = Color(red: 0x2A / 255, green: 0x2F / 255, blue: 0x3C / 255)

    static let cobalt = Color(red: 0x2F / 255, green: 0x5F / 255, blue: 0xE0 / 255)
    static let cobaltLight = Color(red: 0x6D / 255, green: 0x8D / 255, blue: 0xFF / 255)

    /// The rest of LumenMeter's tab/zone accents — used sparingly here to break up tags
    /// and the golden-hour callout rather than leaving everything cobalt-on-cobalt.
    /// (Violet dropped from rotation — low contrast on the dark background, hard to read.)
    static let shutterGreen = Color(red: 0x2E / 255, green: 0xCC / 255, blue: 0x71 / 255)
    static let apertureGold = Color(red: 0xF4 / 255, green: 0xD0 / 255, blue: 0x3F / 255)
    static let warningRed = Color(red: 0xE7 / 255, green: 0x4C / 255, blue: 0x3C / 255)
    static let linkOrange = Color(red: 0xE6 / 255, green: 0x7E / 255, blue: 0x22 / 255)
    static let customTagBright = Color(red: 0xFF / 255, green: 0x3D / 255, blue: 0x9A / 255)

    private static let tagPalette = [cobaltLight, shutterGreen, apertureGold, warningRed]

    /// The small fixed set of tags Vantage suggests out of the box — anything else
    /// (typed by the user, or one of the auto-tags like time-of-day/region/motion)
    /// counts as "custom" and gets the bright color below instead of the rotation.
    private static let builtInTags: Set<String> = ["to shoot", "shot", "needs permission", "seasonal"]

    /// Same tag always lands on the same color (stable hash), so chips stay
    /// distinguishable at a glance without needing a color picker per tag — except
    /// tags with an obvious semantic meaning, which get a fixed color instead.
    static func tagColor(for tag: String) -> Color {
        if tag.lowercased() == "needs permission" { return warningRed }
        if !builtInTags.contains(tag.lowercased()) { return customTagBright }
        return tagPalette[abs(tag.hashValue) % tagPalette.count]
    }

    /// Tag chip text: the tag's own color on iOS, but plain white on the Mac app —
    /// background/border keep using tagColor(for:) on both platforms either way.
    static func tagTextColor(for tag: String) -> Color {
        #if os(iOS)
        tagColor(for: tag)
        #else
        .white
        #endif
    }
}
