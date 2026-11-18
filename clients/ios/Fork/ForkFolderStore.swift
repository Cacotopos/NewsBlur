//
//  ForkFolderStore.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import Foundation

/// A top-level folder as the fork rail shows it.
struct ForkFolder: Equatable {
    /// Key in `appDelegate.dictFolders` (the upstream folder title, e.g. "Blogs - Gaming").
    let key: String
    /// Full title shown in the feed column header.
    let title: String
    /// Short label under the squircle ("Gaming" for "Blogs - Gaming").
    let shortLabel: String
    /// Feed ids in upstream's sort order.
    let feedIds: [String]
    let unread: Int
    /// Feeds ("publications") in the folder with at least one unread story.
    let unreadFeeds: Int

    /// Two-letter initials from the short label ("Gaming" → "Ga").
    var initials: String {
        let letters = shortLabel.filter { $0.isLetter || $0.isNumber }
        let two = String(letters.prefix(2))
        return two.prefix(1).uppercased() + two.dropFirst().lowercased()
    }
}

/// Read-only view of upstream's folder/feed/unread data for the fork UI.
/// All reads go through `NewsBlurAppDelegate`; nothing here mutates upstream state.
enum ForkFolderStore {
    /// Key for top-level feeds that aren't in any folder (upstream renames " " to this).
    static let otherKey = "everything"

    /// Upstream pseudo-folders that never appear in the rail.
    private static let specialKeys: Set<String> = [
        "dashboard", "discover_sites", "daily_briefing", "infrequent", "everything",
        "river_global", "river_blurblogs", "saved_searches", "saved_stories",
        "read_stories", "widget_stories", "try_feed", "widely_read",
    ]

    /// Upstream joins nested folder names with this when the parent exists (`fixFolderNames`).
    private static let nestedSeparator = " ▸ "
    /// Separator inside a top-level folder's own title ("Blogs - Gaming").
    private static let titleSeparator = " - "

    private static var app: NewsBlurAppDelegate? { NewsBlurAppDelegate.shared }

    static func isUserFolder(_ key: String) -> Bool {
        !specialKeys.contains(key) && !key.hasPrefix("trending:") && !key.hasPrefix("river_")
            && !key.contains(nestedSeparator) && !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Top-level folders with at least one feed (muted feeds count), in upstream's order.
    static func topLevelFolders() -> [ForkFolder] {
        guard let app, let order = app.dictFoldersArray as? [String] else { return [] }
        return order.filter(isUserFolder).compactMap { key in
            let ids = feedIds(inFolder: key)
            guard !ids.isEmpty else { return nil }
            return ForkFolder(key: key, title: key, shortLabel: shortLabel(for: key),
                              feedIds: ids, unread: unread(feedIds: ids), unreadFeeds: unreadFeeds(feedIds: ids))
        }
    }

    /// The "Other" pseudo-folder: top-level feeds outside any folder.
    static func otherFolder() -> ForkFolder {
        let ids = feedIds(inFolder: otherKey)
        return ForkFolder(key: otherKey, title: "Other", shortLabel: "Other",
                          feedIds: ids, unread: unread(feedIds: ids), unreadFeeds: unreadFeeds(feedIds: ids))
    }

    static func shortLabel(for title: String) -> String {
        guard let range = title.range(of: titleSeparator, options: .backwards) else { return title }
        let tail = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return tail.isEmpty ? title : tail
    }

    /// Feeds in a folder that upstream knows about, muted (inactive) ones included, in upstream's order.
    static func feedIds(inFolder key: String) -> [String] {
        guard let app, let raw = app.dictFolders?[key] as? [Any] else { return [] }
        return raw.map { "\($0)" }.filter { app.dictFeeds?[$0] != nil }
    }

    /// False for feeds the user muted. Upstream keeps muted feeds in `dictFeeds` with `active = 0`.
    static func isActiveFeed(_ feedId: String) -> Bool {
        guard let feed = app?.dictFeeds?[feedId] as? [AnyHashable: Any] else { return false }
        return (feed["active"] as? NSNumber)?.boolValue ?? true
    }

    /// Unread = positive + neutral, matching upstream's "All" filter (hidden stories excluded).
    /// Muted feeds count as 0, like upstream's folder counts.
    static func unread(feedId: String) -> Int {
        guard isActiveFeed(feedId), let counts = app?.dictUnreadCounts?[feedId] as? [AnyHashable: Any] else { return 0 }
        let ps = (counts["ps"] as? NSNumber)?.intValue ?? 0
        let nt = (counts["nt"] as? NSNumber)?.intValue ?? 0
        return max(0, ps) + max(0, nt)
    }

    static func unread(feedIds: [String]) -> Int {
        feedIds.reduce(0) { $0 + unread(feedId: $1) }
    }

    static func unreadFeeds(feedIds: [String]) -> Int {
        feedIds.filter { unread(feedId: $0) > 0 }.count
    }
}
