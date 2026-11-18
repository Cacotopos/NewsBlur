//
//  ForkTheme.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import UIKit

/// Fork colours for all four upstream themes: [light, warm/sepia, medium, dark].
/// Colours are resolved at call time from `ThemeManager`, so re-read them when the theme changes.
enum ForkTheme {
    private static func c(_ light: Int, _ sepia: Int, _ medium: Int, _ dark: Int) -> UIColor {
        ThemeManager.color(fromRGB: [NSNumber(value: light), NSNumber(value: sepia),
                                     NSNumber(value: medium), NSNumber(value: dark)])
    }

    static var railBackground: UIColor { c(0xE8E8E4, 0xE8DED0, 0x2A2A2A, 0x161616) }
    static var railBorder: UIColor { c(0xD9D9D4, 0xD4C8B8, 0x222222, 0x000000) }
    static var squircle: UIColor { c(0xFFFFFF, 0xFAF5ED, 0x444444, 0x2A2A2A) }
    static var squircleText: UIColor { c(0x3B3B36, 0x5C4A3A, 0xDDDDDD, 0xD0D0D0) }
    static var squircleSelected: UIColor { c(0x33332F, 0x5C4A3A, 0xEEEEEE, 0xE6E6E6) }
    static var squircleSelectedText: UIColor { c(0xFFFFFF, 0xFAF5ED, 0x222222, 0x111111) }
    static var badge: UIColor { c(0x6B6C64, 0x8B7B6B, 0x8F918B, 0x6F716B) }
    static var badgeText: UIColor { c(0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF) }
    static var railLabel: UIColor { c(0x4A4A44, 0x6B5B4B, 0xBBBBBB, 0xAAAAAA) }
    static var railLabelSelected: UIColor { c(0x1F1F1C, 0x3B2E22, 0xFFFFFF, 0xFFFFFF) }

    /// Identifies the visual theme, to notice changes.
    static var current: String { ThemeManager.shared.effectiveTheme ?? "" }
}
