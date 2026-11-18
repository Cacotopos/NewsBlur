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

    /// True while the fork's own columns are on screen and upstream's split must show only the reader.
    static var ownsLayout: Bool {
        guard let root, root.isViewLoaded else { return false }
        return root.isWide
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
