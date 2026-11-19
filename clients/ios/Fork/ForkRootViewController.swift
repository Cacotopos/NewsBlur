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
/// Docked (wide, not full screen): rail (fixed) · feed column (2/8) · upstream's split, held to its
/// reader column by `ForkSplitViewController`.
/// Reader-only (compact, or wide with full screen on): the split fills the window and the menu button
/// in the reader header slides the rail + feed column in as an overlay (SPEC "Compact").
final class ForkRootViewController: UIViewController {
    /// Window width at or above which the fork shows its columns (SPEC "Wide").
    static let wideThreshold: CGFloat = 1000

    let upstreamSplit: UIViewController
    let rail = ForkRailViewController()
    let feedColumn = ForkFeedColumnViewController()

    /// Dims the reader behind the overlay panel; tapping it closes the overlay.
    private let backdrop = UIControl()

    private var refreshTimer: Timer?
    private var feedsObserver: NSObjectProtocol?

    /// Full screen chosen with the reader's full-screen button. Only matters while wide.
    private(set) var readerFullScreen = false
    /// Rail + feed column shown over the reader while it is reader-only.
    private(set) var overlayOpen = false
    private var lastColumnsDocked: Bool?

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

    /// Rail and feed column sit beside the reader. Otherwise the reader fills the window.
    var columnsDocked: Bool { isWide && !readerFullScreen }

    // MARK: - Reader-only and overlay

    /// The reader's full-screen button (hook in `DetailViewController.swift`). Wide only.
    func toggleReaderFullScreen() {
        guard isWide else { return }
        readerFullScreen.toggle()
        overlayOpen = false
        animateLayout()
    }

    func setOverlay(open: Bool, animated: Bool = true) {
        guard !columnsDocked, open != overlayOpen else { return }
        overlayOpen = open
        if animated { animateLayout() } else { view.setNeedsLayout() }
    }

    @objc private func closeOverlay() { setOverlay(open: false) }

    private func animateLayout() {
        // Show the panel before it slides in; hide it after it slides out (keeps it out of VoiceOver).
        setPanelHidden(false)
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut]) {
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }

    private var panelVisible: Bool { columnsDocked || overlayOpen }

    private func setPanelHidden(_ hidden: Bool) {
        rail.view.isHidden = hidden
        feedColumn.view.isHidden = hidden
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "fork-root"

        addChild(upstreamSplit)
        view.addSubview(upstreamSplit.view)
        upstreamSplit.didMove(toParent: self)

        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        backdrop.alpha = 0
        backdrop.accessibilityLabel = NSLocalizedString("Close menu", comment: "Fork overlay backdrop")
        backdrop.addTarget(self, action: #selector(closeOverlay), for: .touchUpInside)
        view.addSubview(backdrop)

        addChild(feedColumn)
        view.addSubview(feedColumn.view)
        feedColumn.didMove(toParent: self)

        addChild(rail)
        view.addSubview(rail.view)
        rail.didMove(toParent: self)
        rail.onSelect = { [weak self] folder in self?.feedColumn.show(folder: folder) }
        feedColumn.onOpenStory = { [weak self] in self?.setOverlay(open: false) }
        feedColumn.onClose = { [weak self] in self?.setOverlay(open: false) }

        // Upstream posts no notification when unread counts change (marking read, sync),
        // so poll cheaply in addition to the full-reload notification. No upstream hook needed.
        feedsObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("FinishedLoadingFeedsNotification"), object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAll() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startRefreshTimer()
        // Reader-only at launch: the reader starts empty, so start with the menu open.
        if !columnsDocked { setOverlay(open: true, animated: false) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.panelVisible, UIApplication.shared.applicationState == .active else { return }
            self.refreshAll()
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // Docking again (e.g. rotating to landscape) closes the overlay.
        if size.width >= Self.wideThreshold, !readerFullScreen { overlayOpen = false }
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.view.setNeedsLayout() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let railWidth = ForkRailViewController.railWidth
        let wideColumnWidth = (bounds.width * 2 / 8).rounded()
        if columnsDocked {
            overlayOpen = false
            rail.view.frame = CGRect(x: 0, y: 0, width: railWidth, height: bounds.height)
            feedColumn.view.frame = CGRect(x: railWidth, y: 0, width: wideColumnWidth, height: bounds.height)
            let readerX = railWidth + wideColumnWidth
            upstreamSplit.view.frame = CGRect(x: readerX, y: 0, width: bounds.width - readerX, height: bounds.height)
        } else {
            // Wide full screen: the overlay is a panel at docked widths. Compact: 3/4 of the window, so the
            // reader stays visible behind it (SPEC, user 2026-11-20).
            let panelWidth = isWide ? railWidth + wideColumnWidth : (bounds.width * 3 / 4).rounded()
            let panelX = overlayOpen ? 0 : -panelWidth
            rail.view.frame = CGRect(x: panelX, y: 0, width: railWidth, height: bounds.height)
            feedColumn.view.frame = CGRect(x: panelX + railWidth, y: 0, width: panelWidth - railWidth, height: bounds.height)
            upstreamSplit.view.frame = bounds
        }
        backdrop.frame = bounds
        backdrop.alpha = overlayOpen ? 1 : 0
        backdrop.isUserInteractionEnabled = overlayOpen
        feedColumn.showsCloseButton = !columnsDocked
        if UIView.inheritedAnimationDuration == 0 { setPanelHidden(!panelVisible) }
        (upstreamSplit as? ForkSplitViewController)?.enforceReaderOnly()

        if lastColumnsDocked != columnsDocked {
            lastColumnsDocked = columnsDocked
            ForkUI.readerButtonsNeedUpdate()
        }
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
