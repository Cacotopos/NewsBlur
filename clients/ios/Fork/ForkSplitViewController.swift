//
//  ForkSplitViewController.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import UIKit

/// Keeps upstream's split view showing only its reader column while the fork owns the layout.
///
/// `ForkUI.install` swaps the class of upstream's existing `SplitViewController` instance to this
/// subclass (`object_setClass`), so no upstream file needs a hook. This class must never add stored
/// properties, or the swap would be unsafe.
final class ForkSplitViewController: SplitViewController {
    /// Upstream calls these from many places (feed selection, sidebar toggles, Duo logic).
    /// While the fork's columns are visible, the feeds and story-titles columns stay hidden.
    override var preferredDisplayMode: UISplitViewController.DisplayMode {
        get { super.preferredDisplayMode }
        set { super.preferredDisplayMode = ForkUI.ownsLayout ? .secondaryOnly : newValue }
    }

    override func show(_ column: UISplitViewController.Column) {
        if ForkUI.ownsLayout, column != .secondary { return }
        super.show(column)
    }

    override var presentsWithGesture: Bool {
        get { ForkUI.ownsLayout ? false : super.presentsWithGesture }
        set { super.presentsWithGesture = newValue }
    }

    /// Re-applies the reader-only mode, e.g. after a change from compact to wide.
    func enforceReaderOnly() {
        guard ForkUI.ownsLayout else { return }
        if super.preferredDisplayMode != .secondaryOnly { super.preferredDisplayMode = .secondaryOnly }
        if displayMode != .secondaryOnly {
            NSLog("ForkSplit: enforcing reader-only (displayMode=%d, style=%d)", displayMode.rawValue, style.rawValue)
            hide(.primary)
            if style == .tripleColumn { hide(.supplementary) }
        }
    }
}
