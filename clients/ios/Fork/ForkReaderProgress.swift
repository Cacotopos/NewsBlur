//
//  ForkReaderProgress.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import UIKit

/// Where the open story sits in its feed (user's pick, 2026-11-20): a thin amber bar under the reader
/// header that fills as you go, and a pill at the bottom of the reader, e.g. "7 of 21 · 14 unread".
///
/// Reads upstream's `StoriesCollection`, which is the list swiping and Next walk (the fork keeps it on
/// the feed column's All/Unread, see `ForkFeedColumnViewController.open`). Stories not loaded yet are
/// counted from the feed's live unread count, so in Unread the total is exact; in All it counts what's
/// loaded plus the unread still to come, and says so with a "+".
/// `ForkRootViewController` owns both views and lays them out over the reader. Neither takes touches.
final class ForkReaderProgress {
    let bar = BarView()
    let pill = PillView()

    struct Position: Equatable {
        let index: Int
        let total: Int
        let unread: Int
        let more: Bool
    }

    /// Position of the open story, or nil when there's nothing to show (no story, or a river of folders).
    static func current() -> Position? {
        guard let app = NewsBlurAppDelegate.shared, let collection = app.storiesCollection,
              !collection.isRiverOrSocial,
              let hash = (app.activeStory as? [String: Any])?["story_hash"] as? String,
              let stories = collection.activeFeedStories as? [[String: Any]],
              let locations = collection.activeFeedStoryLocations as? [NSNumber] else { return nil }
        let list = locations.compactMap { $0.intValue < stories.count ? stories[$0.intValue] : nil }
        guard let index = list.firstIndex(where: { $0["story_hash"] as? String == hash }) else { return nil }

        let feedId = collection.activeFeedIdStr ?? ""
        let unreadNow = ForkFolderStore.unread(feedId: feedId)
        let unreadLoaded = list.filter { !(($0["read_status"] as? NSNumber)?.boolValue ?? false) }.count
        let unreadNotLoaded = max(0, unreadNow - unreadLoaded)
        let total = max(list.count + unreadNotLoaded, index + 1)
        let more = collection.activeReadFilter == "all"
        return Position(index: index, total: total, unread: unreadNow, more: more)
    }

    func show(_ position: Position?) {
        bar.isHidden = position == nil
        pill.isHidden = position == nil
        guard let position else { return }
        bar.fraction = CGFloat(position.index + 1) / CGFloat(max(position.total, 1))
        pill.text = Self.text(position)
    }

    func applyTheme() {
        bar.applyTheme()
        pill.applyTheme()
    }

    private static func text(_ p: Position) -> String {
        let place = String(format: NSLocalizedString("%1$d of %2$d%3$@", comment: "Fork reader position, e.g. 7 of 21"),
                           p.index + 1, p.total, p.more ? "+" : "")
        let unread = String(format: NSLocalizedString("%d unread", comment: "Fork reader unread left in feed"), p.unread)
        return "\(place) · \(unread)"
    }

    /// Thin bar: a faint track with an amber fill.
    final class BarView: UIView {
        private let fill = UIView()
        var fraction: CGFloat = 0 { didSet { setNeedsLayout() } }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            addSubview(fill)
            fill.backgroundColor = UIColor(red: 1, green: 0xB2 / 255.0, blue: 0x3F / 255.0, alpha: 0.85)
            applyTheme()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        func applyTheme() { backgroundColor = ForkTheme.separator }

        override func layoutSubviews() {
            super.layoutSubviews()
            fill.frame = CGRect(x: 0, y: 0, width: bounds.width * min(max(fraction, 0), 1), height: bounds.height)
        }
    }

    /// Rounded label in the reader's bottom toolbar row, on the same glass as upstream's Text and Next buttons.
    final class PillView: UIView {
        private let glass = UIVisualEffectView(effect: UIGlassEffect())
        private let label = UILabel()
        var text: String? {
            get { label.text }
            set {
                label.text = newValue
                accessibilityLabel = newValue
                invalidateIntrinsicContentSize()
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = true
            accessibilityTraits = .staticText
            glass.layer.cornerRadius = 22
            glass.layer.cornerCurve = .continuous
            glass.clipsToBounds = true
            addSubview(glass)
            label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
            label.textAlignment = .center
            glass.contentView.addSubview(label)
            applyTheme()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        func applyTheme() { label.textColor = ForkTheme.text }

        override var intrinsicContentSize: CGSize {
            let size = label.intrinsicContentSize
            return CGSize(width: size.width + 36, height: 44)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            glass.frame = bounds
            label.frame = glass.contentView.bounds
        }
    }
}
