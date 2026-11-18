//
//  ForkFeedColumnViewController.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import UIKit

/// Column 2 (SPEC "Feed column"): the selected folder's feeds as collapsible sections, each feed's
/// stories inline beneath it. Feeds are never interleaved: every story sits under its own feed.
final class ForkFeedColumnViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Row: Equatable {
        case feed(String)
        case story(ForkStory)
        case more(feedId: String)
        case status(feedId: String, text: String)
        case quietGroup(count: Int)
    }

    private static let readFilterDefaults = "fork_read_filter"
    /// SPEC: more than this many zero-unread feeds collapse into one row.
    private static let quietCollapseThreshold = 3

    private let titleLabel = UILabel()
    private let filterControl = UISegmentedControl(items: [
        NSLocalizedString("All", comment: "Fork feed column filter"),
        NSLocalizedString("Unread", comment: "Fork feed column filter"),
    ])
    private let header = UIView()
    private let titleRow = UIStackView()
    private let closeButton = UIButton(type: .system)
    private let headerBorder = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let border = UIView()

    private var folder: ForkFolder?
    /// Feed order, frozen when the folder opens so rows don't jump while the user reads.
    private var activeFeedIds: [String] = []
    private var quietFeedIds: [String] = []
    private var quietExpanded = false
    private var expandedFeeds: [String: Set<String>] = [:] // folder key → open feed ids
    private var storiesByFeed: [String: ForkFeedStories] = [:]
    private var rows: [Row] = []
    private var selectedStoryHash: String?
    private var lastTheme = ""

    /// Called after a story is sent to the reader (the root closes the overlay).
    var onOpenStory: (() -> Void)?
    /// Called by the header's close button.
    var onClose: (() -> Void)?

    /// The close button shows only while the column is an overlay (SPEC "Compact").
    var showsCloseButton = false {
        didSet { if isViewLoaded { closeButton.isHidden = !showsCloseButton } }
    }

    private var readFilter: String {
        get { UserDefaults.standard.string(forKey: Self.readFilterDefaults) ?? "unread" }
        set { UserDefaults.standard.set(newValue, forKey: Self.readFilterDefaults) }
    }

    // MARK: - View

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "fork-feed-column"

        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        closeButton.accessibilityLabel = NSLocalizedString("Close", comment: "Fork feed column overlay close")
        closeButton.accessibilityIdentifier = "fork-close-menu"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        closeButton.isHidden = !showsCloseButton

        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 8
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(closeButton)
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        filterControl.selectedSegmentIndex = readFilter == "all" ? 0 : 1
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        filterControl.accessibilityIdentifier = "fork-read-filter"
        filterControl.translatesAutoresizingMaskIntoConstraints = false

        header.translatesAutoresizingMaskIntoConstraints = false
        headerBorder.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleRow)
        header.addSubview(filterControl)
        header.addSubview(headerBorder)
        view.addSubview(header)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        tableView.register(ForkFeedCell.self, forCellReuseIdentifier: ForkFeedCell.reuseId)
        tableView.register(ForkStoryCell.self, forCellReuseIdentifier: ForkStoryCell.reuseId)
        tableView.register(ForkInfoCell.self, forCellReuseIdentifier: ForkInfoCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        border.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(border)

        let hairline = 1 / max(1, traitCollection.displayScale)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: guide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: border.leadingAnchor),

            titleRow.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            titleRow.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            titleRow.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            titleRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

            filterControl.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 10),
            filterControl.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            filterControl.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            filterControl.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -10),

            headerBorder.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerBorder.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerBorder.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            headerBorder.heightAnchor.constraint(equalToConstant: hairline),

            tableView.topAnchor.constraint(equalTo: header.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: border.leadingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            border.topAnchor.constraint(equalTo: view.topAnchor),
            border.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            border.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            border.widthAnchor.constraint(equalToConstant: hairline),
        ])
        applyTheme()
    }

    private func applyTheme() {
        lastTheme = ForkTheme.current
        view.backgroundColor = ForkTheme.columnBackground
        tableView.backgroundColor = ForkTheme.columnBackground
        header.backgroundColor = ForkTheme.columnHeader
        headerBorder.backgroundColor = ForkTheme.separator
        border.backgroundColor = ForkTheme.railBorder
        titleLabel.textColor = ForkTheme.text
        closeButton.tintColor = ForkTheme.secondaryText
        tableView.reloadData()
    }

    // MARK: - Public

    /// Shows a folder. Re-showing the same folder keeps open feeds and loaded stories.
    func show(folder newFolder: ForkFolder) {
        let isSameFolder = newFolder.key == folder?.key
        folder = newFolder
        titleLabel.text = newFolder.title
        if !isSameFolder { quietExpanded = false }
        recomputeOrder()
        rebuildRows()
        if !isSameFolder { tableView.setContentOffset(.zero, animated: false) }
    }

    /// Shows the folder only if a different one (or none) is showing; used by the periodic refresh.
    func show(folderIfChanged newFolder: ForkFolder) {
        guard newFolder.key != folder?.key else { return }
        show(folder: newFolder)
    }

    /// Called about once a second: picks up unread counts, read state and theme changes cheaply.
    func refreshLiveState() {
        guard isViewLoaded else { return }
        if ForkTheme.current != lastTheme { applyTheme() }
        guard let folder else { return }
        // Folder membership may change after a sync; counts are re-read by visible cells.
        let ids = ForkFolderStore.feedIds(inFolder: folder.key)
        if Set(ids) != Set(activeFeedIds + quietFeedIds) {
            recomputeOrder()
            rebuildRows()
            return
        }
        var changed = syncReadStateFromUpstream()
        for cell in tableView.visibleCells {
            if let cell = cell as? ForkFeedCell, cell.refreshCount() { changed = true }
        }
        if changed { rebuildRows() }
    }

    // MARK: - Model

    private func recomputeOrder() {
        guard let folder else { activeFeedIds = []; quietFeedIds = []; return }
        let ids = ForkFolderStore.feedIds(inFolder: folder.key)
        activeFeedIds = ids.filter { ForkFolderStore.unread(feedId: $0) > 0 }
        quietFeedIds = ids.filter { ForkFolderStore.unread(feedId: $0) == 0 }
    }

    private var openFeeds: Set<String> {
        get { folder.map { expandedFeeds[$0.key] ?? [] } ?? [] }
        set { if let key = folder?.key { expandedFeeds[key] = newValue } }
    }

    private func stories(for feedId: String) -> ForkFeedStories {
        let key = "\(feedId)|\(readFilter)"
        if let existing = storiesByFeed[key] { return existing }
        let created = ForkFeedStories(feedId: feedId, readFilter: readFilter)
        storiesByFeed[key] = created
        return created
    }

    private func rebuildRows() {
        var result: [Row] = []
        let open = openFeeds
        func appendFeed(_ feedId: String) {
            result.append(.feed(feedId))
            guard open.contains(feedId) else { return }
            let loaded = stories(for: feedId)
            for story in loaded.stories { result.append(.story(story)) }
            if loaded.isLoading {
                result.append(.status(feedId: feedId, text: NSLocalizedString("Loading…", comment: "Fork feed column")))
            } else if loaded.failed {
                result.append(.status(feedId: feedId, text: NSLocalizedString("Couldn't load stories. Tap to retry.", comment: "Fork feed column")))
            } else if loaded.stories.isEmpty && loaded.reachedEnd {
                result.append(.status(feedId: feedId, text: NSLocalizedString("No stories", comment: "Fork feed column")))
            } else if !loaded.reachedEnd && !(readFilter == "unread" && allUnreadShown(loaded)) {
                result.append(.more(feedId: feedId))
            }
        }
        activeFeedIds.forEach(appendFeed)
        if quietFeedIds.count > Self.quietCollapseThreshold {
            result.append(.quietGroup(count: quietFeedIds.count))
            if quietExpanded { quietFeedIds.forEach(appendFeed) }
        } else {
            quietFeedIds.forEach(appendFeed)
        }
        rows = result
        tableView.reloadData()
    }

    /// In Unread mode, nothing is left to page in once every unread story is on screen.
    private func allUnreadShown(_ loaded: ForkFeedStories) -> Bool {
        let shownUnread = loaded.stories.filter { !$0.isRead }.count
        return !loaded.stories.isEmpty && ForkFolderStore.unread(feedId: loaded.feedId) <= shownUnread
    }

    private func toggle(feedId: String) {
        var open = openFeeds
        if open.contains(feedId) {
            open.remove(feedId)
        } else {
            open.insert(feedId)
            let loaded = stories(for: feedId)
            if loaded.stories.isEmpty && !loaded.reachedEnd { load(loaded) }
        }
        openFeeds = open
        rebuildRows()
    }

    private func load(_ loaded: ForkFeedStories) {
        loaded.loadNextPage { [weak self] in self?.rebuildRows() }
    }

    /// Upstream marks stories read in its own collection; mirror that here.
    private func syncReadStateFromUpstream() -> Bool {
        guard let collection = NewsBlurAppDelegate.shared?.storiesCollection,
              let upstream = collection.activeFeedStories as? [[String: Any]], !upstream.isEmpty else { return false }
        var states: [String: Bool] = [:]
        for story in upstream {
            if let hash = story["story_hash"] as? String {
                states[hash] = (story["read_status"] as? NSNumber)?.boolValue ?? false
            }
        }
        var changed = false
        for loaded in storiesByFeed.values where loaded.syncReadState(from: states) { changed = true }
        return changed
    }

    // MARK: - Actions

    @objc private func filterChanged() {
        readFilter = filterControl.selectedSegmentIndex == 0 ? "all" : "unread"
        // Drop cached pages for the new filter so Unread really hides what's been read since.
        storiesByFeed = storiesByFeed.filter { !$0.key.hasSuffix("|\(readFilter)") }
        for feedId in openFeeds { load(stories(for: feedId)) }
        rebuildRows()
    }

    private func open(_ story: ForkStory) {
        selectedStoryHash = story.hash
        for loaded in storiesByFeed.values { loaded.markRead(hash: story.hash) }
        rebuildRows()
        guard let app = NewsBlurAppDelegate.shared else { return }
        // Upstream normally finds the story by paging its (hidden) story list, which stalls past page 1.
        // Marking it as a pending notification story makes `loadFeed:withStory:` look it up by hash
        // instead (`/reader/river_stories?h=`). The property is readonly in the header, so set it via KVC.
        app.setValue(["feedId": story.feedId, "storyHash": story.hash], forKey: "pendingNotificationStory")
        // Upstream loads the feed and opens the story in its reader; prev/next walks this feed.
        app.loadFeed(story.feedId, withStory: story.hash, storyTitle: story.title, animated: false)
        onOpenStory?()
    }

    @objc private func closeTapped() { onClose?() }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch rows[indexPath.row] {
        case .feed(let feedId):
            let cell = tableView.dequeueReusableCell(withIdentifier: ForkFeedCell.reuseId, for: indexPath) as! ForkFeedCell
            cell.configure(feedId: feedId, isOpen: openFeeds.contains(feedId))
            return cell
        case .story(let story):
            let cell = tableView.dequeueReusableCell(withIdentifier: ForkStoryCell.reuseId, for: indexPath) as! ForkStoryCell
            cell.configure(story: story, selected: story.hash == selectedStoryHash)
            return cell
        case .more(let feedId):
            let cell = tableView.dequeueReusableCell(withIdentifier: ForkInfoCell.reuseId, for: indexPath) as! ForkInfoCell
            cell.configure(text: moreText(feedId: feedId), style: .action, indent: true)
            return cell
        case .status(_, let text):
            let cell = tableView.dequeueReusableCell(withIdentifier: ForkInfoCell.reuseId, for: indexPath) as! ForkInfoCell
            cell.configure(text: text, style: .muted, indent: true)
            return cell
        case .quietGroup(let count):
            let cell = tableView.dequeueReusableCell(withIdentifier: ForkInfoCell.reuseId, for: indexPath) as! ForkInfoCell
            let format = NSLocalizedString("%d feeds with nothing unread", comment: "Fork feed column collapsed group")
            cell.configure(text: String(format: format, count), style: .group(open: quietExpanded), indent: false)
            return cell
        }
    }

    private func moreText(feedId: String) -> String {
        let loaded = stories(for: feedId)
        if readFilter == "unread" {
            let shownUnread = loaded.stories.filter { !$0.isRead }.count
            let remaining = ForkFolderStore.unread(feedId: feedId) - shownUnread
            if remaining > 0 {
                let format = NSLocalizedString("Show %d more unread", comment: "Fork feed column pagination")
                return String(format: format, remaining)
            }
        }
        return NSLocalizedString("Show more", comment: "Fork feed column pagination")
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        switch rows[indexPath.row] {
        case .feed(let feedId):
            toggle(feedId: feedId)
        case .story(let story):
            open(story)
        case .more(let feedId):
            load(stories(for: feedId))
            rebuildRows()
        case .status(let feedId, _):
            let loaded = stories(for: feedId)
            if loaded.failed { load(loaded); rebuildRows() }
        case .quietGroup:
            quietExpanded.toggle()
            rebuildRows()
        }
    }
}

// MARK: - Cells

private final class ForkFeedCell: UITableViewCell {
    static let reuseId = "ForkFeedCell"

    private let chevron = UIImageView()
    private let icon = UIImageView()
    private let nameLabel = UILabel()
    private let countLabel = UILabel()
    private let separator = UIView()
    private var feedId: String?
    private var shownCount = -1

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        chevron.contentMode = .scaleAspectFit
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        icon.contentMode = .scaleAspectFit
        icon.layer.cornerRadius = 3
        icon.clipsToBounds = true
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        for subview in [chevron, icon, nameLabel, countLabel, separator] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        let hairline = 1 / max(1, traitCollection.displayScale)
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            chevron.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            icon.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.topAnchor.constraint(equalTo: contentView.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: hairline),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(feedId: String, isOpen: Bool) {
        self.feedId = feedId
        let app = NewsBlurAppDelegate.shared
        let feed = app?.dictFeeds?[feedId] as? [AnyHashable: Any]
        nameLabel.text = (feed?["feed_title"] as? String) ?? feedId
        icon.image = app?.getFavicon(feedId)
        chevron.image = UIImage(systemName: isOpen ? "chevron.down" : "chevron.right")
        backgroundColor = isOpen ? ForkTheme.feedRowOpen : ForkTheme.columnBackground
        separator.backgroundColor = ForkTheme.separator
        chevron.tintColor = ForkTheme.secondaryText
        nameLabel.textColor = ForkTheme.text
        countLabel.textColor = ForkTheme.count
        shownCount = -1
        _ = refreshCount()
        accessibilityIdentifier = "fork-feed-\(feedId)"
    }

    /// Updates the unread count in place; returns true when a feed crossed to or from zero.
    @discardableResult
    func refreshCount() -> Bool {
        guard let feedId else { return false }
        let count = ForkFolderStore.unread(feedId: feedId)
        guard count != shownCount else { return false }
        let crossedZero = shownCount >= 0 && (shownCount == 0) != (count == 0)
        shownCount = count
        countLabel.text = count > 0 ? "\(count)" : ""
        let muted = count == 0
        nameLabel.alpha = muted ? 0.45 : 1
        icon.alpha = muted ? 0.45 : 1
        return crossedZero
    }
}

private final class ForkStoryCell: UITableViewCell {
    static let reuseId = "ForkStoryCell"

    private let dot = UIView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        dot.layer.cornerRadius = 3.5
        titleLabel.numberOfLines = 3
        titleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        dateLabel.font = .systemFont(ofSize: 11)
        for subview in [dot, titleLabel, dateLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            dot.topAnchor.constraint(equalTo: titleLabel.topAnchor, constant: 6),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 42),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            dateLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            dateLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(story: ForkStory, selected: Bool) {
        titleLabel.text = story.title
        dateLabel.text = story.date
        titleLabel.textColor = story.isRead ? ForkTheme.readText : ForkTheme.text
        dateLabel.textColor = ForkTheme.secondaryText
        dot.backgroundColor = ForkTheme.unreadDot
        dot.isHidden = story.isRead
        backgroundColor = selected ? ForkTheme.selectedRow : ForkTheme.columnBackground
        accessibilityIdentifier = "fork-story-\(story.hash)"
    }
}

private final class ForkInfoCell: UITableViewCell {
    static let reuseId = "ForkInfoCell"
    enum Style { case action, muted, group(open: Bool) }

    private let label = UILabel()
    private let chevron = UIImageView()
    private var leading: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.numberOfLines = 2
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevron.contentMode = .scaleAspectFit
        for subview in [label, chevron] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        leading = label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 42)
        NSLayoutConstraint.activate([
            leading,
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            chevron.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(text: String, style: Style, indent: Bool) {
        label.text = text
        backgroundColor = ForkTheme.columnBackground
        switch style {
        case .action:
            label.textColor = ForkTheme.count
            chevron.isHidden = true
        case .muted:
            label.textColor = ForkTheme.secondaryText
            chevron.isHidden = true
        case .group(let open):
            label.textColor = ForkTheme.readText
            chevron.isHidden = false
            chevron.image = UIImage(systemName: open ? "chevron.down" : "chevron.right")
            chevron.tintColor = ForkTheme.readText
        }
        leading.constant = indent ? 42 : 32
    }
}
