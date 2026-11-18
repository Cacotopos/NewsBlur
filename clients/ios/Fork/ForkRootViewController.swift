//
//  ForkRootViewController.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import UIKit

/// Window root for the iPad fork.
///
/// Upstream's `SplitViewController` stays alive as a child: the app delegate keeps its reference
/// and presents modals from it.
///
/// Wide: rail (fixed) · feed column (2/8) · upstream's split, held to its reader column by
/// `ForkSplitViewController`. Compact (M7): upstream fills the window for now.
final class ForkRootViewController: UIViewController {
    /// Window width at or above which the fork shows its columns (SPEC "Wide").
    static let wideThreshold: CGFloat = 1000

    let upstreamSplit: UIViewController
    let rail = ForkRailViewController()
    let feedColumn = ForkFeedColumnViewController()

    private var refreshTimer: Timer?
    private var feedsObserver: NSObjectProtocol?

    init(upstreamSplit: UIViewController) {
        self.upstreamSplit = upstreamSplit
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        refreshTimer?.invalidate()
        if let feedsObserver { NotificationCenter.default.removeObserver(feedsObserver) }
    }

    var isWide: Bool { view.bounds.width >= Self.wideThreshold }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "fork-root"

        addChild(upstreamSplit)
        view.addSubview(upstreamSplit.view)
        upstreamSplit.didMove(toParent: self)

        addChild(feedColumn)
        view.addSubview(feedColumn.view)
        feedColumn.didMove(toParent: self)

        addChild(rail)
        view.addSubview(rail.view)
        rail.didMove(toParent: self)
        rail.onSelect = { [weak self] folder in self?.feedColumn.show(folder: folder) }

        // Upstream posts no notification when unread counts change (marking read, sync),
        // so poll cheaply in addition to the full-reload notification. No upstream hook needed.
        feedsObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("FinishedLoadingFeedsNotification"), object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAll() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startRefreshTimer()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isWide, UIApplication.shared.applicationState == .active else { return }
            self.refreshAll()
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        if isWide {
            let railWidth = ForkRailViewController.railWidth
            let columnWidth = (bounds.width * 2 / 8).rounded()
            rail.view.isHidden = false
            feedColumn.view.isHidden = false
            rail.view.frame = CGRect(x: 0, y: 0, width: railWidth, height: bounds.height)
            feedColumn.view.frame = CGRect(x: railWidth, y: 0, width: columnWidth, height: bounds.height)
            let readerX = railWidth + columnWidth
            upstreamSplit.view.frame = CGRect(x: readerX, y: 0, width: bounds.width - readerX, height: bounds.height)
        } else {
            // Compact mode (overlay) arrives in M7; until then upstream fills the window.
            rail.view.isHidden = true
            feedColumn.view.isHidden = true
            upstreamSplit.view.frame = bounds
        }
        (upstreamSplit as? ForkSplitViewController)?.enforceReaderOnly()
    }

    // MARK: - Refresh

    /// Rail counts, then the feed column for whichever folder the rail has selected.
    private func refreshAll() {
        rail.refresh()
        if let folder = rail.selectedFolder { feedColumn.show(folderIfChanged: folder) }
        feedColumn.refreshLiveState()
    }

    // Let upstream keep control of the status bar and home indicator.
    override var childForStatusBarStyle: UIViewController? { upstreamSplit }
    override var childForStatusBarHidden: UIViewController? { upstreamSplit }
    override var childForHomeIndicatorAutoHidden: UIViewController? { upstreamSplit }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { upstreamSplit }
}
