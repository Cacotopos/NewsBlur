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
/// M4 (interim): in wide mode the folder rail takes a fixed-width strip on the left and upstream's split fills the rest.
/// M5/M6 add the feed column and shrink the split to the reader.
final class ForkRootViewController: UIViewController {
    /// Window width at or above which the fork shows its columns (SPEC "Wide").
    static let wideThreshold: CGFloat = 1000

    let upstreamSplit: UIViewController
    let rail = ForkRailViewController()

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

        addChild(rail)
        view.addSubview(rail.view)
        rail.didMove(toParent: self)
        rail.onSelect = { [weak self] folder in self?.didSelect(folder) }

        // Upstream posts no notification when unread counts change (marking read, sync),
        // so poll cheaply in addition to the full-reload notification. No upstream hook needed.
        feedsObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("FinishedLoadingFeedsNotification"), object: nil, queue: .main
        ) { [weak self] _ in self?.rail.refresh() }
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
            self.rail.refresh()
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
            rail.view.isHidden = false
            rail.view.frame = CGRect(x: 0, y: 0, width: railWidth, height: bounds.height)
            upstreamSplit.view.frame = CGRect(x: railWidth, y: 0, width: bounds.width - railWidth, height: bounds.height)
        } else {
            // Compact mode (overlay) arrives in M7; until then upstream fills the window.
            rail.view.isHidden = true
            upstreamSplit.view.frame = bounds
        }
    }

    // MARK: - Selection

    private func didSelect(_ folder: ForkFolder) {
        // Interim until the feed column (M5): show the folder's river in upstream's story list.
        guard folder.key != ForkFolderStore.otherKey,
              let app = NewsBlurAppDelegate.shared,
              let order = app.dictFoldersArray as? [String],
              let index = order.firstIndex(of: folder.key) else { return }
        app.feedsViewController.didSelectSectionHeader(withTag: index)
    }

    // Let upstream keep control of the status bar and home indicator.
    override var childForStatusBarStyle: UIViewController? { upstreamSplit }
    override var childForStatusBarHidden: UIViewController? { upstreamSplit }
    override var childForHomeIndicatorAutoHidden: UIViewController? { upstreamSplit }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { upstreamSplit }
}
