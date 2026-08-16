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
}
