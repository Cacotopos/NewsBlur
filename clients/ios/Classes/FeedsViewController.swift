//
//  FeedsViewController.swift
//  NewsBlur
//
//  Created by David Sinclair on 2020-08-27.
//  Copyright © 2020 NewsBlur. All rights reserved.
//

import UIKit
import StoreKit

/// Storyboard shell for the hidden primary column.
///
/// FORK: `FeedsObjCViewController` is gone; the feed-list engine it hosted now
/// lives in `Fork/ForkFeedEngine.swift` (reachable as `appDelegate.feedEngine`).
/// This class survives only because `MainInterface.storyboard` instantiates it
/// as the split's primary column and KVC-wires the outlets below at launch.
/// Everything else is stubs: the table renders zero rows, the wired actions
/// forward to the engine or do nothing, and dead navigation actions are no-ops.
class FeedsViewController: BaseViewController {

    // MARK: - Storyboard outlets

    @IBOutlet var innerView: UIView!
    @IBOutlet var feedTitlesTable: UITableView!
    @IBOutlet var feedTitlesTopConstraint: NSLayoutConstraint!
    @IBOutlet var feedTitlesLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var feedTitlesTrailingConstraint: NSLayoutConstraint!
    @IBOutlet var toolbarLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var toolbarTrailingConstraint: NSLayoutConstraint!
    @IBOutlet var toolbarBottomConstraint: NSLayoutConstraint!
    @IBOutlet var feedViewToolbar: UIToolbar!
    @IBOutlet var intelligenceControl: UISegmentedControl!
    @IBOutlet var noFocusMessage: UIView!
    @IBOutlet var noFocusLabel: UILabel!
    @IBOutlet var addBarButton: UIBarButtonItem!
    @IBOutlet var settingsBarButton: UIBarButtonItem!

    // Code-created members external code reads through feedsViewController.
    @objc var searchField: UITextField?
    @objc var syncNotifier: SyncNotifierView!

    // MARK: - Dead feed-list UI (kept as stubs; the column is hidden in CE)

    override func updateTheme() {}
    @objc func updateSidebarButton() {}
    @objc(updateSidebarButtonForDisplayMode:) func updateSidebarButton(for displayMode: UISplitViewController.DisplayMode) {}
    @objc func resetToolbar() {}
    @objc(selectDashboard:) func selectDashboard(_ sender: Any?) {}
    @objc func anyFolderExpanded() -> Bool { false }
    @objc(didCollapseFolder:) func didCollapseFolder(_ sender: Any?) {}
    @objc(didToggleAllFolders:) func didToggleAllFolders(_ sender: Any?) {}
    @objc(sectionTapped:) func sectionTapped(_ sender: Any?) {}
    @objc(sectionUntapped:) func sectionUntapped(_ sender: Any?) {}
    @objc(sectionUntappedOutside:) func sectionUntappedOutside(_ sender: Any?) {}
    @IBAction func showSettingsPopover(_ sender: Any) {}
    @IBAction func tapAddSite(_ sender: Any) {}

    /// Storyboard action for the hidden segmented control; the selection state
    /// itself lives in `selectedIntelligence`, owned by the engine.
    @IBAction func selectIntelligence() {
        appDelegate.feedEngine.selectIntelligence()
    }

    // MARK: - App Store review prompt (kept from the original implementation)

    struct Keys {
        static let reviewDate = "datePromptedForReview"
        static let reviewVersion = "versionPromptedForReview"
    }

    var appearCount = 0

    lazy var appVersion: String = {
        let infoDictionaryKey = kCFBundleVersionKey as String

        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String else {
            fatalError("Expected to find a bundle version in the info dictionary")
        }

        return currentVersion
    }()

    var datePromptedForReview: Date {
        get {
            guard let date = UserDefaults.standard.object(forKey: Keys.reviewDate) as? Date else {
                let date = Date()
                UserDefaults.standard.set(date, forKey: Keys.reviewDate)
                return date
            }

            return date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.reviewDate)
        }
    }

    var versionPromptedForReview: String {
        get {
            return UserDefaults.standard.string(forKey: Keys.reviewVersion) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.reviewVersion)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        appearCount += 1

        let month: TimeInterval = 60 * 60 * 24 * 30
        let promptedDate = datePromptedForReview
        let currentVersion = appVersion
        let promptedVersion = versionPromptedForReview

        // We only get a few prompts per year, so only ask for a review if gone back to the Feeds list several times, it's been at least a month since the last prompt, and it's a different version.
        if appearCount >= 5, -promptedDate.timeIntervalSinceNow > month, currentVersion != promptedVersion, let scene = view.window?.windowScene {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [navigationController] in
                if navigationController?.topViewController is FeedsViewController {
                    SKStoreReviewController.requestReview(in: scene)
                    self.datePromptedForReview = Date()
                    self.versionPromptedForReview = currentVersion
                }
            }
        }
    }
}

// MARK: - Empty table data source

/// The storyboard connects `feedTitlesTable`'s dataSource/delegate to this
/// controller. Delegate calls `reloadData` on it; returning zero rows keeps
/// that a no-op without crashing on the required data-source methods.
extension FeedsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        UITableViewCell()
    }
}
