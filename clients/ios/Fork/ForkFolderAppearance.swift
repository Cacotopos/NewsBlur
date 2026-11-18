//
//  ForkFolderAppearance.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import UIKit

/// How a folder's squircle in the rail is drawn, chosen from its long-press menu.
enum ForkFolderIcon: Equatable {
    case initials
    case symbol(String)
    case firstFeed
}

/// Per-folder icon and short-label choices, stored on this device only (UserDefaults).
///
/// Keyed by the upstream folder title (`ForkFolder.key`). Renaming a folder on the website starts
/// it fresh with initials and the automatic label.
enum ForkFolderAppearance {
    private static let iconsKey = "fork_folder_icons"
    private static let labelsKey = "fork_folder_labels"
    /// Short labels longer than this don't fit under the 56 pt squircle in the 88 pt rail.
    static let maxLabelLength = 14

    static func icon(for folderKey: String) -> ForkFolderIcon {
        guard let stored = storedIcons[folderKey] else { return .initials }
        if stored == "firstFeed" { return .firstFeed }
        if stored.hasPrefix("symbol:") { return .symbol(String(stored.dropFirst("symbol:".count))) }
        return .initials
    }

    static func setIcon(_ icon: ForkFolderIcon, for folderKey: String) {
        var icons = storedIcons
        switch icon {
        case .initials: icons[folderKey] = nil
        case .symbol(let name): icons[folderKey] = "symbol:\(name)"
        case .firstFeed: icons[folderKey] = "firstFeed"
        }
        UserDefaults.standard.set(icons, forKey: iconsKey)
    }

    /// The user's own short label, or nil for the automatic one.
    static func customLabel(for folderKey: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: labelsKey) as? [String: String])?[folderKey]
    }

    /// Saves a custom short label; an empty one goes back to the automatic label.
    static func setCustomLabel(_ label: String?, for folderKey: String) {
        var labels = (UserDefaults.standard.dictionary(forKey: labelsKey) as? [String: String]) ?? [:]
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        labels[folderKey] = trimmed.isEmpty ? nil : String(trimmed.prefix(maxLabelLength))
        UserDefaults.standard.set(labels, forKey: labelsKey)
    }

    /// The label shown under the squircle.
    static func label(for folder: ForkFolder) -> String {
        customLabel(for: folder.key) ?? folder.shortLabel
    }

    /// Two-letter initials from the shown label, so a renamed label also changes the initials.
    static func initials(for folder: ForkFolder) -> String {
        let letters = label(for: folder).filter { $0.isLetter || $0.isNumber }
        let two = String(letters.prefix(2))
        return two.prefix(1).uppercased() + two.dropFirst().lowercased()
    }

    private static var storedIcons: [String: String] {
        (UserDefaults.standard.dictionary(forKey: iconsKey) as? [String: String]) ?? [:]
    }
}
