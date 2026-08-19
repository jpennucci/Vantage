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

    /// The starter suggestions (tapped, not typed) plus every fixed-vocabulary
    /// auto-tag (time-of-day, motion) — reliably identifiable from the string alone.
    /// Region tags are auto-applied too but are dynamic place names with no fixed
    /// vocabulary to list here, so those rely on the entry's own `autoTags` record
    /// instead (see the `isAutoTag:` overload below).
    private static let builtInTags: Set<String> = [
        "to shoot", "shot", "needs permission", "seasonal",
        "night", "blue hour", "golden hour", "midday",
        "driving", "on foot", "stationary"
    ]

    /// Built-in/auto tags all share one color (orange, matching LumenMeter's accent
    /// language) so they read as "system-applied" at a glance; anything the user
    /// actually typed themselves gets the bright custom color instead. "Needs
    /// permission" keeps its own warning color regardless, since that's a meaningful
    /// status. This string-only overload is for chips not yet tied to a specific
    /// entry (the "tap to add" suggestion row); prefer the `isAutoTag:` overload
    /// wherever a tag is already applied to an entry; it's authoritative for region
    /// tags, which this vocabulary check alone can't recognize.
    static func tagColor(for tag: String) -> Color {
        if tag.lowercased() == "needs permission" { return warningRed }
        if !builtInTags.contains(tag.lowercased()) { return customTagBright }
        return linkOrange
    }

    static func tagColor(for tag: String, isAutoTag: Bool) -> Color {
        if tag.lowercased() == "needs permission" { return warningRed }
        if isAutoTag || builtInTags.contains(tag.lowercased()) { return linkOrange }
        return customTagBright
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

    static func tagTextColor(for tag: String, isAutoTag: Bool) -> Color {
        #if os(iOS)
        tagColor(for: tag, isAutoTag: isAutoTag)
        #else
        .white
        #endif
    }
}
