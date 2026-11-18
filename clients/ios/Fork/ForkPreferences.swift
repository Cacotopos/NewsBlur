//
//  ForkPreferences.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import UIKit

/// Trims upstream's Preferences to what still means something under the fork's layout, and reads the
/// list settings the fork's feed column honors (story order, list text size).
///
/// Called from hook H10 at the end of `PreferencesViewModel.buildSections()` in `Classes/PreferencesView.swift`.
enum ForkPreferences {
    /// Settings for upstream's feed list and story list, which the fork's rail and feed column replace.
    /// Kept in UserDefaults untouched, so turning the fork off brings them back as they were.
    static let hiddenKeys: Set<String> = [
        // Story List: the feed column's All/Unread control and inline stories replace these.
        "default_folder_read_filter", "default_feed_read_filter", "default_confirm_read_filter",
        "after_mark_read", "feed_opening", "discover_display", "story_clustering", "cluster_mode",
        // Story Layout: upstream's story titles list only.
        "story_toolbar_position", "story_titles_position", "story_titles_style",
        "story_list_preview_text_size", "story_list_preview_images_size",
        // Feed List: the rail replaces upstream's feed list and its special rows.
        "feed_list_sort_order", "show_feeds_after_being_read", "app_opening",
        "show_infrequent_site_stories", "infrequent_stories_per_month", "show_global_shared_stories",
        "show_widely_read_stories", "show_long_reads", "show_good_reads",
        // Gestures on feed rows and story titles, which the fork doesn't show.
        "enable_feed_swipes", "feed_title_swipe_left", "feed_title_swipe_right", "long_press_feed_title",
        "enable_story_swipes", "story_title_swipe_left", "story_title_swipe_right", "long_press_story_title",
    ]

    /// Drops hidden items, then any group or section left with nothing in it.
    static func filtered(_ sections: [PreferenceSection]) -> [PreferenceSection] {
        guard ForkUI.isActive else { return sections }
        return sections.compactMap { section in
            if section.groups.isEmpty {
                let items = section.items.filter(isShown)
                guard !items.isEmpty else { return nil }
                return PreferenceSection(title: section.title, icon: section.icon, iconColor: section.iconColor,
                                         footerText: section.footerText, items: items)
            }
            let groups = section.groups.compactMap { group -> PreferenceGroup? in
                let items = group.items.filter(isShown)
                return items.isEmpty ? nil : PreferenceGroup(title: group.title, footer: group.footer, items: items)
            }
            guard !groups.isEmpty else { return nil }
            return PreferenceSection(title: section.title, icon: section.icon, iconColor: section.iconColor,
                                     footerText: section.footerText, groups: groups)
        }
    }

    private static func isShown(_ item: PreferenceItem) -> Bool {
        guard let key = key(of: item) else { return true }
        return !hiddenKeys.contains(key)
    }

    private static func key(of item: PreferenceItem) -> String? {
        switch item.type {
        case .toggle(let key, _), .multiValue(let key, _, _, _), .slider(let key, _, _, _, _, _),
             .textField(let key, _, _), .button(let key, _), .staticValue(let key, _):
            return key
        case .link, .language, .appIcon:
            return nil
        }
    }

    // MARK: - Settings the feed column honors

    /// Upstream's "Story order" (`default_order`): "newest" or "oldest".
    static var storyOrder: String {
        UserDefaults.standard.string(forKey: "default_order") == "oldest" ? "oldest" : "newest"
    }

    /// Multiplier for the feed column's fonts, from upstream's "Feed and story list" text size.
    /// The column's base sizes match upstream's "medium" (14 pt story titles), as in `FeedDetailTableCell.m`.
    static var listFontScale: CGFloat {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "use_system_font_size") {
            return UIFontMetrics(forTextStyle: .body).scaledValue(for: 14) / 14
        }
        let titleSizes: [String: CGFloat] = ["xs": 11, "small": 13, "medium": 14, "large": 16, "xl": 18]
        return (titleSizes[defaults.string(forKey: "feed_list_font_size") ?? "medium"] ?? 14) / 14
    }
}
