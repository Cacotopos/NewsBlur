//
//  ForkRootViewController.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import UIKit

/// Window root for the iPad fork.
///
/// Upstream's `SplitViewController` stays alive as a child: the app delegate keeps its reference
/// and presents modals from it. M2: the split fills the whole view (upstream UI unchanged).
/// Later milestones add the rail and feed column beside it, and shrink the split to the reader frame.
final class ForkRootViewController: UIViewController {
    let upstreamSplit: UIViewController

    init(upstreamSplit: UIViewController) {
        self.upstreamSplit = upstreamSplit
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "fork-root"
        addChild(upstreamSplit)
        upstreamSplit.view.frame = view.bounds
        upstreamSplit.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(upstreamSplit.view)
        upstreamSplit.didMove(toParent: self)
    }

    // Let upstream keep control of the status bar and home indicator.
    override var childForStatusBarStyle: UIViewController? { upstreamSplit }
    override var childForStatusBarHidden: UIViewController? { upstreamSplit }
    override var childForHomeIndicatorAutoHidden: UIViewController? { upstreamSplit }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { upstreamSplit }
}
