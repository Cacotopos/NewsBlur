//
//  ForkUI.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import UIKit

/// Entry point and master switch for the iPad fork UI.
///
/// `isEnabled` defaults to on. Turn it off to get upstream's UI back when debugging a bad merge:
/// - launch argument `-fork_ui_enabled NO` (Xcode scheme → Arguments), or
/// - `xcrun simctl spawn booted defaults write com.newsblur.NewsBlur fork_ui_enabled -bool NO`.
@objcMembers
final class ForkUI: NSObject {
    static let enabledDefaultsKey = "fork_ui_enabled"

    /// Master switch. Read from UserDefaults so launch arguments override it.
    static var isEnabled: Bool {
        // bool(forKey:) also parses the string "NO"/"YES" that a launch argument supplies.
        let defaults = UserDefaults.standard
        return defaults.object(forKey: enabledDefaultsKey) == nil ? true : defaults.bool(forKey: enabledDefaultsKey)
    }

    /// The fork only takes over on iPad, outside Mac Catalyst.
    static var isActive: Bool {
#if targetEnvironment(macCatalyst)
        return false
#else
        return isEnabled && UIDevice.current.userInterfaceIdiom == .pad
#endif
    }

    /// The installed fork root, if any.
    private(set) static weak var root: ForkRootViewController?

    /// True while the fork owns the layout and upstream's split must show only the reader.
    /// That is any iPad window the fork root fills, docked or reader-only.
    static var ownsLayout: Bool {
        guard let root, root.isViewLoaded else { return false }
        return true
    }

    // MARK: - Reader header buttons (hooks in upstream's toolbar code)

    /// Hook in `DetailViewController.toggleTemporaryFullScreen`. Returns true when the fork handled it.
    static func toggleReaderFullScreen() -> Bool {
        guard ownsLayout, let root else { return false }
        root.toggleReaderFullScreen()
        return true
    }

    /// Hook in `StoryPagesObjCViewController.m`: the fork's full-screen state, for the button icon.
    static var isReaderFullScreen: Bool { (root?.isWide ?? false) && (root?.readerFullScreen ?? false) }

    /// Hook in `StoryPagesObjCViewController.m`: full screen means nothing while compact.
    static var hidesFullScreenButton: Bool { ownsLayout && !(root?.isWide ?? false) }

    // MARK: - Login (hook in upstream's app delegate)

    /// Hook H12 in `NewsBlurAppDelegate.showLogin`. Upstream presents the login screen from its feed
    /// list only while that list is in the window, which it never is under the fork, so a logged-out
    /// app showed an empty fork screen. Presents it from the top of the fork root instead.
    /// Returns true when the fork handled it. The login screen dismisses itself, so no other hook is needed.
    static func presentLogin(_ login: UIViewController) -> Bool {
        guard ownsLayout, let root else { return false }
        guard login.presentingViewController == nil else { return true }
        var top: UIViewController = root
        while let presented = top.presentedViewController { top = presented }
        top.present(login, animated: false)
        return true
    }

    /// Hook in `FeedDetailObjCViewController.m`: the button at the top left of the reader.
    /// Opens the overlay while reader-only; hidden while the columns are docked.
    static var readerMenuButton: UIBarButtonItem? {
        guard let root, !root.columnsDocked else { return nil }
        return menuButton
    }

    private static let menuButton: UIBarButtonItem = {
        let image = UIImage(systemName: "sidebar.leading") ?? UIImage(systemName: "sidebar.left")
        let button = UIBarButtonItem(image: image, style: .plain, target: ForkUI.self, action: #selector(openMenu))
        button.accessibilityLabel = NSLocalizedString("Folders", comment: "Fork reader menu button")
        button.accessibilityIdentifier = "fork-menu"
        return button
    }()

    @objc private static func openMenu() { root?.setOverlay(open: true) }

    /// Re-runs upstream's code that fills the reader header, after the fork's layout changes.
    static func readerButtonsNeedUpdate() {
        guard let app = NewsBlurAppDelegate.shared else { return }
        if let split = app.splitViewController {
            app.feedDetailViewController?.updateSidebarButton(for: split.displayMode)
        }
        app.detailViewController?.storyPagesViewController?.updateStoryTitleNavigationButtons()
    }

    /// Called once from `SceneDelegate` after `prepareViewControllers()`.
    /// Re-parents upstream's split view controller into the fork root. No-op when inactive.
    static func install(in window: UIWindow?, split: UIViewController?) {
        guard isActive, let window, let split, root == nil,
              window.rootViewController === split else {
            NSLog("ForkUI: not installed (enabled=%d, active=%d)", isEnabled, isActive)
            return
        }
        // Swap in the fork subclass so the split keeps to its reader column (no upstream hook needed).
        if type(of: split) == SplitViewController.self {
            object_setClass(split, ForkSplitViewController.self)
        }
        let forkRoot = ForkRootViewController(upstreamSplit: split)
        window.rootViewController = forkRoot
        root = forkRoot
        NSLog("ForkUI: installed fork root around %@", String(describing: type(of: split)))
    }
}
