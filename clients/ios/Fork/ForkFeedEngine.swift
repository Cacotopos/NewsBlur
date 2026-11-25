//
//  ForkFeedEngine.swift
//  NewsBlur
//
//  FORK: Replaces the non-UI engine half of FeedsObjCViewController for the CE
//  fork. FeedsViewController survives only as the storyboard shell (the hidden
//  primary column still KVC-wires IBOutlets at launch); everything the fork
//  actually needs — feed-list sync, unread counts, mark-read, next-unread
//  navigation, offline cache load, notification-story hook — lives here.
//
//  Dropped on purpose: the feed-list table/swipe/search/pull-to-refresh UI,
//  toolbars and menus, dashboard rivers, feed management, and the sync/caching
//  notifiers (SyncNotifierView lives in the hidden VC's view, so they were
//  already no-ops; the methods remain as stubs so call sites stay unchanged).

import UIKit

@objc(ForkFeedEngine)
@objcMembers
final class ForkFeedEngine: NSObject, PreferencesViewDelegate {

    // Indices in foldersArray; keep in sync with NewsBlurTopSection.
    private static let topSectionNames = [/* 0 */ "dashboard",
                                          /* 1 */ "discover_sites",
                                          /* 2 */ "daily_briefing",
                                          /* 3 */ "infrequent",
                                          /* 4 */ "everything"]

    private static let sectionDashboard = 0
    private static let sectionDiscoverSites = 1
    private static let sectionInfrequent = 3
    private static let sectionAllStories = 4

#if DEBUG
    private static let backgroundRefreshSeconds: TimeInterval = 5
#else
    private static let backgroundRefreshSeconds: TimeInterval = 60 * 60
#endif

    weak var viewController: FeedsViewController?

    var appDelegate: NewsBlurAppDelegate {
        guard let appDelegate = NewsBlurAppDelegate.shared else {
            fatalError("ForkFeedEngine used before NewsBlurAppDelegate.shared exists")
        }
        return appDelegate
    }

    // These collections are nil until /reader/feeds lands (and after
    // showLogin's reset). ObjC callers messaged nil harmlessly; the Swift
    // port reads them through these fallbacks so pre-load callers — the
    // bottom next-feed control, visibility checks — get the same empty
    // answer instead of an IUO trap.
    private var foldersArray: NSMutableArray { appDelegate.dictFoldersArray ?? NSMutableArray() }
    private var foldersDict: [AnyHashable: Any] { appDelegate.dictFolders ?? [:] }
    private var feedsDict: NSMutableDictionary { appDelegate.dictFeeds ?? NSMutableDictionary() }
    private var inactiveFeedsDict: [AnyHashable: Any] { (appDelegate.dictInactiveFeeds as? [AnyHashable: Any]) ?? [:] }
    private var socialFeedsDict: [AnyHashable: Any] { appDelegate.dictSocialFeeds ?? [:] }
    private var feedIconsDict: [AnyHashable: Any] { appDelegate.dictFeedIcons ?? [:] }
    private var unreadCountsDict: NSMutableDictionary { appDelegate.dictUnreadCounts ?? NSMutableDictionary() }
    private var savedStoryTagsDict: [AnyHashable: Any] { appDelegate.dictSavedStoryTags ?? [:] }
    private var userProfileDict: [AnyHashable: Any] { appDelegate.dictUserProfile ?? [:] }
    private var folderCountCacheDict: NSMutableDictionary { appDelegate.folderCountCache ?? NSMutableDictionary() }

    @objc var isOffline = false
    @objc var viewShowingAllFeeds = false
    @objc var interactiveFeedDetailTransition = false
    @objc var stillVisibleFeeds = NSMutableDictionary()
    @objc var activeFeedLocations = NSMutableDictionary()
    @objc var visibleFolders = NSMutableDictionary()
    @objc var searchFeedIds: [String]?
    @objc var currentRowAtIndexPath: IndexPath?
    @objc var lastRowAtIndexPath: IndexPath?
    @objc var currentSection = 0
    @objc var lastSection = 0
    @objc var feedListAccountGeneration: UInt = 0
    @objc var feedListRequestGeneration: UInt = 0
    @objc var awaitingAuthenticatedFeedList = false
    @objc var inPullToRefresh = false
    @objc var imageCache = NSCache<AnyObject, AnyObject>()
    var leftAppDate: Date?
    var loadWorkItem: DispatchWorkItem?
    var reloadWorkItem: DispatchWorkItem?
    var lastFeedTitlesReloadTime = Date.distantPast

    override init() {
        super.init()
        let appOpening = UserDefaults.standard.string(forKey: "app_opening")
        currentSection = appOpening == "feeds" ? -1 : Self.sectionAllStories
        lastSection = Self.sectionAllStories
    }

    // MARK: - User profile preferences

    private static func userProfilePreferences(_ userProfile: [AnyHashable: Any]?) -> [String: Any]? {
        switch userProfile?["preferences"] {
        case let dictionary as [String: Any]:
            return dictionary
        case let string as String:
            guard let data = string.data(using: .utf8),
                  let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return dictionary
        default:
            return nil
        }
    }

    private static func boolPreferenceValue(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber: return number.boolValue
        case let string as String: return (string as NSString).boolValue
        default: return false
        }
    }

    private static func briefingEnabled(from results: [AnyHashable: Any]) -> Bool {
        if let flag = results["briefing_enabled"], !(flag is NSNull) {
            return boolPreferenceValue(flag)
        }
        if let flag = userProfilePreferences(results["user_profile"] as? [AnyHashable: Any])?["briefing_enabled"],
           !(flag is NSNull) {
            return boolPreferenceValue(flag)
        }
        return false
    }

    @objc func syncStoryClusteringDefaults(fromUserProfile userProfile: [AnyHashable: Any]?) {
        guard let preferences = Self.userProfilePreferences(userProfile), !preferences.isEmpty else { return }
        let defaults = UserDefaults.standard

        if let clustering = preferences["story_clustering"], !(clustering is NSNull) {
            defaults.set(Self.boolPreferenceValue(clustering), forKey: "story_clustering")
        }
        if let clusterMode = preferences["cluster_mode"], !(clusterMode is NSNull) {
            defaults.set(StoryClusterDisplayDecision.normalizedClusterTierValue(clusterMode), forKey: "cluster_mode")
        }
    }

    @objc func updateCachedUserProfilePreference(withKey key: String, value: Any?) {
        guard !userProfileDict.isEmpty, !key.isEmpty else { return }
        var userProfile = userProfileDict
        var preferences = Self.userProfilePreferences(userProfile) ?? [:]
        preferences[key] = value ?? ""
        userProfile["preferences"] = preferences
        appDelegate.dictUserProfile = userProfile
    }

    @objc func saveProfilePreference(withKey key: String, value: String) {
        guard !key.isEmpty, !value.isEmpty else { return }
        updateCachedUserProfilePreference(withKey: key, value: value)
        appDelegate.post("\(appDelegate.url ?? "")/profile/set_preference",
                         parameters: [key: value],
                         success: nil,
                         failure: { _, error in
            NSLog("Failed to save %@ preference: %@", key, String(describing: error))
        })
    }

    // MARK: - App lifecycle

    @objc func leavingApp() {
        leftAppDate = Date()
    }

    @objc func returnToApp() {
        let decayDate = Date(timeIntervalSinceNow: -Self.backgroundRefreshSeconds)
        // FeedsObjCViewController.m skips the reload when the realtime socket stayed connected the whole time
        // (the Mac app keeps it open while hidden), since RealtimeUpdates.swift already applied every change.
        if MainActor.assumeIsolated({ RealtimeUpdates.shared.hasStayedConnected(since: leftAppDate) }) { return }
        if let leftAppDate, leftAppDate.timeIntervalSince(decayDate) < 0 {
            appDelegate.reloadFeedsView(true)
        }
    }

    /// FeedsObjCViewController's viewWillAppear restored the intelligence mode
    /// from preferences. Called by the shell's own viewWillAppear.
    @objc func applyIntelligencePreference() {
        let intelligenceLevel = UserDefaults.standard.integer(forKey: "selectedIntelligence")
        if intelligenceLevel == 2 {
            viewShowingAllFeeds = false
            viewController?.intelligenceControl?.selectedSegmentIndex = 3
            appDelegate.selectedIntelligence = 2
        } else if intelligenceLevel == 1 {
            viewShowingAllFeeds = false
            viewController?.intelligenceControl?.selectedSegmentIndex = 2
            appDelegate.selectedIntelligence = 1
        } else if intelligenceLevel == 0 {
            viewShowingAllFeeds = false
            viewController?.intelligenceControl?.selectedSegmentIndex = 1
            appDelegate.selectedIntelligence = 0
        } else {
            viewShowingAllFeeds = true
            viewController?.intelligenceControl?.selectedSegmentIndex = 0
            appDelegate.selectedIntelligence = 0
        }
    }

    @objc func resetForAccountChange() {
        MainActor.assumeIsolated { self.appDelegate.resetFeedSubscriptionForAccountChange() }
        feedListAccountGeneration += 1
        feedListRequestGeneration += 1
        MainActor.assumeIsolated { OnboardingFeedLoading.shared.reset() }
        awaitingAuthenticatedFeedList = true
        cancelPendingFeedListWorkForAccountChange()
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        currentRowAtIndexPath = nil
        lastRowAtIndexPath = nil
        searchFeedIds = nil
        stillVisibleFeeds = NSMutableDictionary()
        activeFeedLocations = NSMutableDictionary()
        isOffline = false
        inPullToRefresh = false
    }

    @objc func cancelPendingFeedListWorkForAccountChange() {
        loadWorkItem?.cancel()
        loadWorkItem = nil
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        clearDashboard()
    }

    // MARK: - Feed list fetch

    @objc func fetchFeedList(_ showLoader: Bool) {
        let accountGeneration = feedListAccountGeneration
        feedListRequestGeneration += 1
        let requestGeneration = feedListRequestGeneration
        NSLog("Fetching feed list")
        appDelegate.cancelOfflineQueue()
        // A feed list load ends in a full count refresh, which covers RealtimeUpdates.swift's catch-up.
        DispatchQueue.main.async { RealtimeUpdates.shared.noteFullCountRefresh() }

        var urlFeedList = "\(appDelegate.url ?? "")/reader/feeds?flat=true&update_counts=\(inPullToRefresh ? "true" : "false")&include_inactive=true"
        if appDelegate.value(forKey: "backgroundAppRefreshTask") != nil {
            urlFeedList += "&background_ios=true"
        }

        appDelegate.get(urlFeedList, parameters: nil as Any?, success: { [weak self] _, responseObject in
            guard let self,
                  accountGeneration == self.feedListAccountGeneration,
                  requestGeneration == self.feedListRequestGeneration else { return }
            self.finishLoadingFeedList(responseObject)
        }, failure: { [weak self] task, error in
            guard let self,
                  accountGeneration == self.feedListAccountGeneration,
                  requestGeneration == self.feedListRequestGeneration else { return }
            MainActor.assumeIsolated { OnboardingFeedLoading.shared.refreshDidFinish() }
            self.finished(with: error, statusCode: (task?.response as? HTTPURLResponse)?.statusCode ?? 0)
        })

        showRefreshNotifier()
    }

    @objc func finished(with error: Error?, statusCode: Int) {
        finishRefresh()
        if statusCode != 403 {
            MainActor.assumeIsolated { self.appDelegate.feedSubscriptionsDidFail() }
        }

        if statusCode == 403 {
            NSLog("Showing login")
            appDelegate.showLogin()
            return
        } else if statusCode >= 400 {
            if statusCode == 429 {
                viewController?.informError("Slow down. You're rate-limited.")
            } else if statusCode == 503 {
                viewController?.informError("In maintenance mode")
            } else {
                viewController?.informError("The server barfed!")
            }

            isOffline = true
            appDelegate.tryFeedStoryId = nil
            appDelegate.tryFeedStoryTitle = nil
            appDelegate.inFindingStoryMode = false
            appDelegate.findingStoryStartDate = nil

            showOfflineNotifier()
            return
        }

        if let view = viewController?.view {
            MBProgressHUD.hide(for: view, animated: true)
        }

        // User clicking on another link before the page loads is OK.
        if let error { viewController?.informError(error) }

        isOffline = true

        showOfflineNotifier()
        loadNotificationStory()
        NotificationCenter.default.post(name: Notification.Name("FinishedLoadingFeedsNotification"), object: nil)
    }

    // FORK: the hidden-table notifiers were already invisible no-ops in CE;
    // they remain as stubs so the ~30 call sites stay unchanged.
    @objc func showRefreshNotifier() { finishRefreshOnboardingAware() }
    @objc func showCountingNotifier() { finishRefreshOnboardingAware() }
    @objc func showSyncingNotifier() { finishRefreshOnboardingAware() }
    @objc func showDoneNotifier() { finishRefreshOnboardingAware() }
    @objc func showSyncingNotifier(_ progress: Float, hoursBack hours: Int) { onboardingAwareOnly() }
    @objc func showCachingNotifier(_ prefix: String, progress: Float, hoursBack hours: Int) { onboardingAwareOnly() }
    @objc func showOfflineNotifier() { onboardingAwareOnly() }
    @objc func hideNotifier() { onboardingAwareOnly() }

    private func onboardingAwareOnly() {
        if MainActor.assumeIsolated({ OnboardingFeedLoading.shared.loading }) { updateOnboardingFeedLoading() }
    }

    private func finishRefreshOnboardingAware() {
        if MainActor.assumeIsolated({ OnboardingFeedLoading.shared.loading }) {
            updateOnboardingFeedLoading()
            return
        }
        finishRefresh()
    }

    @objc func updateOnboardingFeedLoading() {
        if !MainActor.assumeIsolated({ OnboardingFeedLoading.shared.loading }) {
            finishRefresh()
        }
    }

    @objc func finishRefresh() {
        inPullToRefresh = false
    }

    // MARK: - Feed list parse

    @objc func finishLoadingFeedList(_ results: Any?) {
        guard let results = results as? [AnyHashable: Any] else { return }
        let accountGeneration = feedListAccountGeneration
        let requestGeneration = feedListRequestGeneration
        let responseUsername = results["user"] as? String
        let restoresAuthenticatedLayout = awaitingAuthenticatedFeedList
        awaitingAuthenticatedFeedList = false
        appDelegate.hasNoSites = false
        appDelegate.recentlyReadStories = NSMutableDictionary()
        appDelegate.unreadStoryHashes = NSMutableDictionary()
        appDelegate.unsavedStoryHashes = NSMutableDictionary()

        isOffline = false

        appDelegate.activeUsername = results["user"] as? String
        // FeedsObjCViewController.m restores the confirmed account's layout only for its first authenticated response, never an ordinary refresh over a selected article.
        if restoresAuthenticatedLayout,
           appDelegate.detailViewController.restoreDuoFullscreenReader(forAccount: responseUsername) {
            appDelegate.updateSplitBehavior(false)
        }

        let userPreferences = UserDefaults.standard
        let preview = userPreferences.string(forKey: "story_list_preview_images_size")
        let defaults = UserDefaults(suiteName: "group.com.newsblur.NewsBlur-Group")
        defaults?.set(results["share_ext_token"], forKey: "share:token")
        defaults?.set(appDelegate.url, forKey: "share:host")
        defaults?.set(appDelegate.activeUsername, forKey: "share:username")
        defaults?.set(savedStoryTagsDict, forKey: "share:tags")
        defaults?.set(foldersArray, forKey: "share:folders")
        defaults?.set(preview, forKey: "widget:preview_images_size")
        defaults?.set(userPreferences.object(forKey: "infrequent_stories_per_month"), forKey: "widget:infrequent_stories_per_month")
        validateWidgetFeeds(forGroupDefaults: defaults, usingResults: results)
        // FeedsObjCViewController.m publishes the complete catalog for per-widget folder/site selection.
        let widgetCatalog: [String: Any] = ["feeds": results["feeds"] ?? [:],
                                            "flat_folders": results["flat_folders"] ?? [:],
                                            "username": appDelegate.activeUsername ?? "",
                                            "host": appDelegate.url ?? ""]
        if let widgetCatalogData = try? JSONSerialization.data(withJSONObject: widgetCatalog) {
            defaults?.set(widgetCatalogData, forKey: "widget:source_catalog")
        }
        defaults?.synchronize()

        DispatchQueue.global(qos: .default).async { [weak self] in
            guard let self,
                  accountGeneration == self.feedListAccountGeneration,
                  requestGeneration == self.feedListRequestGeneration else { return }
            self.appDelegate.database?.inTransaction { db, _ in
                guard let db,
                      accountGeneration == self.feedListAccountGeneration,
                      requestGeneration == self.feedListRequestGeneration else { return }
                _ = db.executeUpdate("DELETE FROM accounts WHERE username = ?", withArgumentsIn: [responseUsername as Any])
                let feedsJson = (try? JSONSerialization.data(withJSONObject: results))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                _ = db.executeUpdate("INSERT INTO accounts(username, download_date, feeds_json) VALUES (?, ?, ?)",
                                     withArgumentsIn: [responseUsername as Any, Date(), feedsJson])
                for case let feed as [String: Any] in (results["social_feeds"] as? [Any]) ?? [] {
                    _ = db.executeUpdate("INSERT INTO unread_counts (feed_id, ps, nt, ng) VALUES (?, ?, ?, ?)",
                                         withArgumentsIn: [feed["id"] as Any, feed["ps"] as Any, feed["nt"] as Any, feed["ng"] as Any])
                }
                for (_, feedObject) in (results["feeds"] as? [String: Any]) ?? [:] {
                    guard let feed = feedObject as? [String: Any] else { continue }
                    _ = db.executeUpdate("INSERT INTO unread_counts (feed_id, ps, nt, ng) VALUES (?, ?, ?, ?)",
                                         withArgumentsIn: [feed["id"] as Any, feed["ps"] as Any, feed["nt"] as Any, feed["ng"] as Any])
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      accountGeneration == self.feedListAccountGeneration,
                      requestGeneration == self.feedListRequestGeneration else { return }
                self.finishLoadingFeedList(withDict: results, finished: true)
                // FeedsObjCViewController.m syncs the account language only from a network response, never from the
                // offline cache, and only after the feed list is rebuilt for the reload that a language change triggers.
                NBLocalization.syncProfile(results["user_profile"] as? [String: Any])
                if requestGeneration == self.feedListRequestGeneration {
                    MainActor.assumeIsolated { OnboardingFeedLoading.shared.refreshDidFinish() }
                }
            }
        }
    }

    @objc(finishLoadingFeedListWithDict:finished:)
    func finishLoadingFeedList(withDict results: [AnyHashable: Any]!, finished: Bool) {
        let userPreferences = UserDefaults.standard

        if let view = viewController?.view {
            MBProgressHUD.hide(for: view, animated: true)
        }
        stillVisibleFeeds = NSMutableDictionary()

        appDelegate.activeUsername = results?["user"] as? String
        if appDelegate.activeUsername != nil {
            userPreferences.set(appDelegate.activeUsername, forKey: "active_username")
            userPreferences.synchronize()
        }

        viewController?.addBarButton?.accessibilityLabel = NBLocalization.text("Add site")
        viewController?.settingsBarButton?.accessibilityLabel = NBLocalization.text("Settings")
        viewController?.updateSidebarButton()

        let sortedFolders = NSMutableDictionary()

        // Set up dictSocialProfile and userActivitiesArray
        appDelegate.dictUnreadCounts = NSMutableDictionary()
        appDelegate.dictSocialProfile = results?["social_profile"] as? [AnyHashable: Any]
        appDelegate.dictUserProfile = results?["user_profile"] as? [AnyHashable: Any]
        syncStoryClusteringDefaults(fromUserProfile: userProfileDict)
        // FORK: Listen stripped; story button prefs still sync (Fork/ForkStoryButtons.swift).
        ForkStoryButtons.syncFromUserProfile(userProfileDict)
        appDelegate.dictSocialServices = results?["social_services"] as? [AnyHashable: Any]
        appDelegate.userActivitiesArray = results?["activities"] as? [Any]

        appDelegate.dashboardArray = results?["dashboard_rivers"] as? [Any]

        let userProfile = userProfileDict
        appDelegate.isPremium = (userProfile["is_premium"] as? Int ?? 0) == 1
        appDelegate.isPremiumArchive = (userProfile["is_archive"] as? Int ?? 0) == 1
        appDelegate.isPremiumPro = (userProfile["is_pro"] as? Int ?? 0) == 1
        if let premiumExpire = userProfile["premium_expire"], !(premiumExpire is NSNull) {
            appDelegate.premiumExpire = (premiumExpire as? Int) ?? 0
        }

        // Set up dictSocialFeeds
        let socialFeedsArray = (results?["social_feeds"] as? [Any]) ?? []
        let socialFolder = NSMutableArray()
        let socialDict = NSMutableDictionary()
        let tempActiveFeeds = NSMutableDictionary()
        appDelegate.dictActiveFeeds = tempActiveFeeds

        for case let feed as [AnyHashable: Any] in socialFeedsArray {
            guard let feedId = feed["id"] else { continue }
            let userKey = "\(feedId)"
            socialFolder.add(feedId)
            socialDict[userKey] = feed
        }

        appDelegate.dictSocialFeeds = socialDict as! [AnyHashable: Any]

        // set up dictFolders
        var allFolders = NSMutableDictionary()

        if let inactive = results?["flat_folders_with_inactive"] as? NSDictionary {
            allFolders = (inactive.mutableCopy() as? NSMutableDictionary) ?? NSMutableDictionary()
        }

        fixFolderNames(allFolders)

        allFolders["river_blurblogs"] = socialFolder
        allFolders["river_global"] = NSMutableArray()
        allFolders["trending:well_read"] = [Any]()
        allFolders["trending:long_reads"] = [Any]()
        allFolders["trending:good_reads"] = [Any]()

        if let savedSearches = appDelegate.updateSavedSearches(results as? [String: Any]) {
            allFolders["saved_searches"] = savedSearches
        }

        if let savedStories = appDelegate.updateStarredStoryCounts(results as? [String: Any]) {
            allFolders["saved_stories"] = savedStories
        }
        allFolders["daily_briefing"] = [Any]()

        appDelegate.dictFolders = allFolders as! [AnyHashable: Any]
        appDelegate.briefingEnabled = Self.briefingEnabled(from: results ?? [:])

        if let inactiveFeeds = (results?["inactive_feeds"] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary {
            appDelegate.dictInactiveFeeds = inactiveFeeds
        }

        // set up dictFeeds
        let dictFeeds = ((results?["feeds"] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary) ?? NSMutableDictionary()
        dictFeeds.addEntries(from: inactiveFeedsDict)
        appDelegate.dictFeeds = dictFeeds
        appDelegate.populateDictUnreadCounts()
        appDelegate.populateDictTextFeeds()

        // Store custom folder and feed icons
        appDelegate.dictFolderIcons = results?["folder_icons"] as? [AnyHashable: Any]
        appDelegate.dictFeedIcons = results?["feed_icons"] as? [AnyHashable: Any]

        let sortByMostUsed = userPreferences.string(forKey: "feed_list_sort_order") == "usage"

        var sortDescriptors: [NSSortDescriptor] = []

        if sortByMostUsed {
            sortDescriptors.append(NSSortDescriptor(key: "feed_opens", ascending: false))
        }

        let titleDescriptor = NSSortDescriptor(key: "feed_title", ascending: true) { [weak self] obj1, obj2 in
            guard let self else { return .orderedSame }
            // Values may be NSNull for saved-search stubs; ObjC's nil-messaging yielded orderedSame.
            return self.sortableString("\(obj1)").localizedStandardCompare(self.sortableString("\(obj2)"))
        }

        sortDescriptors.append(titleDescriptor)

        // sort all the folders
        appDelegate.dictFoldersArray = NSMutableArray()
        for (folderKey, folderObject) in allFolders {
            guard let folder = folderObject as? [Any] else { continue }
            let folderTitle = (folderKey as? String) == " " ? "everything" : "\(folderKey)"
            foldersArray.add(folderTitle)

            var feeds: [[AnyHashable: Any]] = []

            for feedId in folder {
                let feedIdStr = "\(feedId)"
                let feed: [AnyHashable: Any]?

                if appDelegate.isSavedSearch(feedIdStr) || appDelegate.isSavedFeed(feedIdStr) {
                    feed = ["id": feedId]
                } else if appDelegate.isSocialFeed(feedIdStr) {
                    feed = socialFeedsDict[feedIdStr] as? [AnyHashable: Any]
                } else {
                    feed = feedsDict[feedIdStr] as? [AnyHashable: Any]
                }

                if let feed {
                    feeds.append(feed)
                }
            }

            let sortedFeeds = (feeds as NSArray).sortedArray(using: sortDescriptors)
            let sortedIds = ((sortedFeeds as NSArray).value(forKey: "id") as? [Any]) ?? []

            sortedFolders[folderTitle] = sortedIds
        }

        appDelegate.dictFolders = sortedFolders as! [AnyHashable: Any]
        foldersArray.sort { a, b in
            "\(a)".caseInsensitiveCompare("\(b)")
        }
        // Add feeds from subfolders (addSubfolderFeeds() assigns dictSubfolders itself)
        addSubfolderFeeds()

        // Add all stories etc. to top
        for (sectionIndex, sectionName) in Self.topSectionNames.enumerated() {
            foldersArray.remove(sectionName)
            foldersArray.insert(sectionName, at: sectionIndex)
        }

        let orderedFolders = DailyBriefingFolderPlacementDecision.orderedFolders(folderNames: foldersArray as? [String] ?? [],
                                                                               isEnabled: appDelegate.briefingEnabled)
        appDelegate.dictFoldersArray = NSMutableArray(array: orderedFolders)

        // Add Read Stories folder to bottom
        foldersArray.remove("read_stories")
        foldersArray.add("read_stories")

        // Add Global Shared Stories folder to bottom
        foldersArray.remove("river_global")
        foldersArray.add("river_global")

        // Add trending story folders to bottom
        for trending in ["trending:well_read", "trending:long_reads", "trending:good_reads"] {
            foldersArray.remove(trending)
            foldersArray.add(trending)
        }

        // Add All Shared Stories folder to bottom
        foldersArray.remove("river_blurblogs")
        if socialFeedsDict.count > 0 {
            foldersArray.add("river_blurblogs")
        }

        // Add Saved Searches folder to bottom
        foldersArray.remove("saved_searches")
        if appDelegate.savedSearchesCount > 0 {
            foldersArray.add("saved_searches")
        }

        // Add Saved Stories folder to bottom
        foldersArray.remove("saved_stories")
        if appDelegate.savedStoriesCount > 0 {
            foldersArray.add("saved_stories")
        }

        // test for empty
        if feedsDict.count == 0 && socialFeedsDict.count == 0 {
            appDelegate.hasNoSites = true
        }

        calculateFeedLocations()
        reloadFeedTitlesTable()
        refreshHeaderCounts()

        // assign categories for FTUX
        if let categories = results?["categories"], !(categories is NSNull),
           let categoriesDict = categories as? [AnyHashable: Any] {
            appDelegate.categories = categoriesDict["categories"] as? [Any]
            appDelegate.categoryFeeds = categoriesDict["feeds"] as? [AnyHashable: Any]
        }

        if !isOffline {
            // start up the first time user experience
            if (results?["social_feeds"] as? [Any])?.count ?? 0 == 0,
               (results?["feeds"] as? [AnyHashable: Any])?.count ?? 0 == 0,
               OnboardingViewController.shouldShow(forUsername: appDelegate.activeUsername) {
                appDelegate.showFirstTimeUser()
                // FeedsObjCViewController.m also resumes a first subscription after an authenticated empty feed list.
                if finished {
                    MainActor.assumeIsolated { self.appDelegate.feedSubscriptionsDidLoad() }
                }
                return
            }

            showSyncingNotifier()
            appDelegate.flushQueuedReadStories(true) { [weak self] in
                self?.refreshFeedList()
            }
        }

        viewController?.intelligenceControl?.isHidden = false

        appDelegate.checkForFeedNotifications()

        if appDelegate.pendingDailyBriefingStoryHash != nil {
            loadNotificationStory()
        } else if let pendingFolder = appDelegate.pendingFolder {
            if (appDelegate.splitUnreadCount(forFolder: pendingFolder)?.nt ?? 0) > 0 {
                loadNotificationStory()
            }
        } else {
            loadNotificationStory()
        }

        if finished && !isOffline {
            MainActor.assumeIsolated { self.appDelegate.feedSubscriptionsDidLoad() }
            MainActor.assumeIsolated { RealtimeUpdates.shared.feedListDidLoad() }

            // FeedsViewController.swift offers the language dialog only after a network feed list, never the
            // offline cache; it waits until the reader has rendered and an explicit account language has arrived.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                LanguageDialog.feedListDidLoad()
            }
        }

        NotificationCenter.default.post(name: Notification.Name("FinishedLoadingFeedsNotification"), object: nil)
    }

    @objc func sortableString(_ original: String) -> String {
        var string = original.lowercased()
        string = stripPrefix("the ", from: string)
        string = stripPrefix("a ", from: string)
        string = stripPrefix("an ", from: string)
        return string
    }

    private func stripPrefix(_ prefix: String, from original: String) -> String {
        original.hasPrefix(prefix) ? String(original.dropFirst(prefix.count)) : original
    }

    @objc func fixFolderNames(_ folders: NSMutableDictionary) {
        for key in folders.allKeys {
            guard let folderName = key as? String, folderName.contains(" - "),
                  let folder = folders[folderName] else { continue }
            let components = folderName.components(separatedBy: " - ")
            let parentComponents = components.dropLast()
            let rawParentName = parentComponents.joined(separator: " - ")
            let tidyParentName = parentComponents.joined(separator: " ▸ ")
            let tidyName = components.joined(separator: " ▸ ")

            if folders[rawParentName] != nil || folders[tidyParentName] != nil {
                folders[folderName] = nil
                folders[tidyName] = folder
            }
        }
    }

    // MARK: - Offline feed list

    @objc func loadOfflineFeeds(_ failed: Bool) {
        if awaitingAuthenticatedFeedList { return }
        let accountGeneration = feedListAccountGeneration
        let requestGeneration = feedListRequestGeneration
        isOffline = true
        NSLog("Loading offline feeds: %d", failed)
        let userPreferences = UserDefaults.standard
        if appDelegate.activeUsername == nil {
            appDelegate.activeUsername = userPreferences.string(forKey: "active_username")
            if appDelegate.activeUsername == nil {
                if failed {
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          accountGeneration == self.feedListAccountGeneration,
                          requestGeneration == self.feedListRequestGeneration else { return }
                    self.fetchFeedList(true)
                }
                return
            }
        }

        showRefreshNotifier()
        let accountUsername = appDelegate.activeUsername

        appDelegate.database?.inDatabase { [weak self] db in
            guard let self, let db,
                  accountGeneration == self.feedListAccountGeneration,
                  requestGeneration == self.feedListRequestGeneration else { return }
            var results: [AnyHashable: Any]?

            if let cursor = try? db.executeQuery("SELECT * FROM accounts WHERE username = ? LIMIT 1",
                                                 withArgumentsIn: [accountUsername as Any]) {
                while cursor.next() {
                    if let feedsCache = cursor.resultDictionary(),
                       let feedsJson = feedsCache["feeds_json"] as? String,
                       let data = feedsJson.data(using: .utf8) {
                        results = try? JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any]
                    }
                    break
                }
                cursor.close()
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      accountGeneration == self.feedListAccountGeneration,
                      requestGeneration == self.feedListRequestGeneration else { return }
                self.finishLoadingFeedList(withDict: results, finished: failed)
                self.fetchFeedList(false)
            }
        }
    }

    // MARK: - Folder path helpers (from FeedsViewController.swift)

    @objc func addSubfolderFeeds() {
        let folders = NSMutableDictionary(dictionary: foldersDict)
        let subfolders = NSMutableDictionary()
        for case let folderName as String in foldersArray {
            addSubfolderFeeds(for: folderName, folders: folders, subfolders: subfolders)
        }
        appDelegate.dictFolders = folders as! [AnyHashable: Any]
        appDelegate.dictSubfolders = subfolders as! [AnyHashable: Any]
    }

    private func addSubfolderFeeds(for folderTitle: String, folders: NSMutableDictionary, subfolders: NSMutableDictionary) {
        guard let parentTitle = parentTitle(for: folderTitle),
              let childFeeds = folders[folderTitle] as? [AnyHashable],
              let parentFeeds = folders[parentTitle] as? [AnyHashable] else {
            return
        }

        let existingSubfolders = subfolders[parentTitle] as? [AnyHashable] ?? []

        folders[parentTitle] = unique(parentFeeds + childFeeds)
        subfolders[parentTitle] = unique(existingSubfolders + childFeeds)

        addSubfolderFeeds(for: parentTitle, folders: folders, subfolders: subfolders)
    }

    private func unique(_ array: [AnyHashable]) -> [AnyHashable] {
        var seen = Set<AnyHashable>()
        return array.filter { seen.insert($0).inserted }
    }

    @objc(parentTitleForFolderTitle:)
    func parentTitle(for folderTitle: String) -> String? {
        guard let range = folderTitle.range(of: " ▸ ", options: .backwards) else { return nil }
        return String(folderTitle[..<range.lowerBound])
    }

    @objc(parentTitlesForFolderTitle:)
    func parentTitles(for folderTitle: String) -> [String] {
        guard let parentTitle = parentTitle(for: folderTitle) else { return [] }
        return [parentTitle] + parentTitles(for: parentTitle)
    }

    @objc(folderTitleForFullFolderPath:)
    func folderTitle(for fullFolderPath: String) -> String? {
        fullFolderPath.components(separatedBy: " ▸ ").last
    }

    @objc(fullFolderPathForFolderTitle:)
    func fullFolderPath(for folderTitle: String) -> String? {
        for case let folder as String in foldersArray
        where folder.components(separatedBy: " ▸ ").last == folderTitle {
            return folder
        }
        return nil
    }

    // MARK: - Mark read

    @objc func markFeedRead(_ feedId: String, cutoffDays days: Int) {
        markFeedsRead([feedId], cutoffDays: days)
    }

    @objc func markFeedsRead(_ feedIds: [Any], cutoffDays days: Int) {
        if feedIds.count == 1,
           let first = feedIds.first as? String,
           ["dashboard", "everything", "infrequent"].contains(first) {
            markEverythingRead(withDays: days, infrequent: first == "infrequent")
            return
        }

        let account = appDelegate.activeUsername ?? ""
        let host = appDelegate.url ?? ""
        let cutoffTimestamp = Date().timeIntervalSince1970 - TimeInterval(days * 60 * 60 * 24)

        let urlString = "\(appDelegate.url ?? "")/reader/mark_feed_as_read"
        let params = NSMutableDictionary()
        params["feed_id"] = feedIds
        if days != 0 {
            params["cutoff_timestamp"] = NSNumber(value: Int(cutoffTimestamp))
        }

        appDelegate.post(urlString, parameters: params, success: { [weak self] _, _ in
            StoryFirstPageCache.shared.invalidateSnapshots(account: account, host: host)
            guard let self,
                  (self.appDelegate.activeUsername ?? "") == account,
                  (self.appDelegate.url ?? "") == host else { return }
            self.finishMarkAllAsRead(params)
        }, failure: { [weak self] _, error in
            guard let self,
                  (self.appDelegate.activeUsername ?? "") == account,
                  (self.appDelegate.url ?? "") == host else { return }
            self.requestFailedMarkStoryRead(error, withParams: params)
        })

        if days == 0 {
            for feedId in feedIds {
                appDelegate.markFeedAllRead(feedId)
            }
        }
    }

    @objc func markEverythingRead(withDays days: Int) {
        markEverythingRead(withDays: days, infrequent: false)
    }

    @objc(markEverythingReadWithDays:infrequent:)
    func markEverythingRead(withDays days: Int, infrequent: Bool) {
        let account = appDelegate.activeUsername ?? ""
        let host = appDelegate.url ?? ""
        let feedIds = appDelegate.allFeedIds() ?? []

        let urlString = "\(appDelegate.url ?? "")/reader/mark_all_as_read"

        let params = NSMutableDictionary()
        params["days"] = NSNumber(value: days)

        if infrequent || appDelegate.storiesCollection.activeFolder == "infrequent" {
            let limit = UserDefaults.standard.integer(forKey: "infrequent_stories_per_month")
            params["infrequent"] = "\(limit)"
        }

        appDelegate.post(urlString, parameters: params, success: { [weak self] _, _ in
            StoryFirstPageCache.shared.invalidateSnapshots(account: account, host: host)
            guard let self,
                  (self.appDelegate.activeUsername ?? "") == account,
                  (self.appDelegate.url ?? "") == host else { return }
            self.finishMarkAllAsRead(params)
        }, failure: { [weak self] _, error in
            guard let self,
                  (self.appDelegate.activeUsername ?? "") == account,
                  (self.appDelegate.url ?? "") == host else { return }
            self.requestFailedMarkStoryRead(error, withParams: params)
        })

        if days == 0 {
            for feedId in feedIds {
                appDelegate.markFeedAllRead(feedId)
            }
            reloadFeedTitlesTable()
        }
    }

    @objc func markVisibleStoriesRead() {
        guard let feedsStories = appDelegate.markVisibleStoriesRead() else { return }
        let urlString = "\(appDelegate.url ?? "")/reader/mark_feed_stories_as_read"
        let params = NSMutableDictionary()
        params["feeds_stories"] = String(data: (try? JSONSerialization.data(withJSONObject: feedsStories)) ?? Data(), encoding: .utf8) ?? "" 

        appDelegate.post(urlString, parameters: params, success: { [weak self] _, _ in
            self?.finishMarkAllAsRead(params)
        }, failure: { [weak self] _, error in
            self?.requestFailedMarkStoryRead(error, withParams: params)
        })
    }

    @objc func requestFailedMarkStoryRead(_ error: Error?, withParams params: NSDictionary) {
        appDelegate.markStoriesRead(params["stories"] as? [AnyHashable: Any],
                                    inFeeds: params["feed_id"] as? [Any],
                                    cutoffTimestamp: (params["cutoff_timestamp"] as? Int) ?? 0)
        showOfflineNotifier()
        isOffline = true
        reloadFeedTitlesTable()
    }

    @objc func finishMarkAllAsRead(_ params: NSDictionary) {
        isOffline = false

        if (params["cutoff_timestamp"] as? Int ?? 0) != 0 {
            var feed: Any?
            if let feedIds = params["feed_id"] as? [Any], feedIds.count == 1 {
                feed = feedIds[0]
            }
            refreshFeedList(feed)
        } else if let feedIds = params["feed_id"] as? [Any] {
            appDelegate.markFeedRead(inCache: feedIds)
        }

        appDelegate.storyPagesViewController.reloadWidget()
    }

    // MARK: - Selection

    private var folderCount: Int {
        appDelegate.hasNoSites ? 0 : foldersArray.count
    }

    private func rowCount(inSection section: Int) -> Int {
        guard !appDelegate.hasNoSites,
              section >= 0, section < foldersArray.count,
              let folderName = foldersArray[section] as? String,
              let folder = foldersDict[folderName] as? [Any] else {
            return 0
        }
        let limit = 5000
        if folder.count > limit {
            NSLog("Folder %@ contains %@ feeds; limiting to %@", folderName, NSNumber(value: folder.count), NSNumber(value: limit))
        }
        return min(folder.count, limit)
    }

    @objc func allIndexPaths() -> [IndexPath] {
        var paths: [IndexPath] = []
        for section in 0..<folderCount {
            for row in 0..<rowCount(inSection: section) {
                paths.append(IndexPath(row: row, section: section))
            }
        }
        return paths
    }

    /// FeedsObjCViewController's tableView:didSelectRowAtIndexPath: minus the
    /// hidden table/cell bookkeeping; this is what populates storiesCollection.
    @objc(selectFeedAtIndexPath:)
    func selectFeed(at indexPath: IndexPath) {
        if appDelegate.hasNoSites { return }

        appDelegate.feedDetailViewController.beginExplicitFeedSelection()
        appDelegate.feedDetailViewController.cancelMarkStoryReadTimer()
        appDelegate.storiesCollection.reset()

        currentRowAtIndexPath = indexPath
        currentSection = -1
        lastRowAtIndexPath = indexPath
        lastSection = -1

        guard indexPath.section < foldersArray.count,
              let folderName = foldersArray[indexPath.section] as? String,
              let feeds = foldersDict[folderName] as? [Any],
              indexPath.row < feeds.count else { return }

        var feedIdStr = "\(feeds[indexPath.row])"
        let searchQuery = appDelegate.searchQuery(forFeedId: feedIdStr)
        let searchFolder = appDelegate.searchFolder(forFeedId: feedIdStr)
        feedIdStr = appDelegate.feedIdWithoutSearchQuery(feedIdStr) ?? feedIdStr

        let preferences = UserDefaults.standard
        if !viewShowingAllFeeds, preferences.bool(forKey: "show_feeds_after_being_read") {
            stillVisibleFeeds[feedIdStr] = indexPath
        }

        clearDashboard()

        if let searchFolder {
            appDelegate.loadRiverFeedDetailView(appDelegate.feedDetailViewController, withFolder: searchFolder)
        } else {
            appDelegate.loadFolder(folderName, feedID: feedIdStr)
        }
        if let searchQuery {
            appDelegate.storiesCollection.inSearch = true
            appDelegate.storiesCollection.searchQuery = searchQuery
            appDelegate.storiesCollection.savedSearchQuery = searchQuery
        }

        if !appDelegate.detailViewController.isPhoneOrCompact {
            appDelegate.feedDetailViewController.viewWillAppear(false)
            appDelegate.feedDetailViewController.viewDidAppear(false)
        }
    }

    @objc(didSelectSectionHeader:)
    func didSelectSectionHeader(_ button: Any) {
        if let button = button as? UIButton {
            didSelectSectionHeader(withTag: button.tag)
        }
    }

    @objc(didSelectSectionHeaderWithTag:)
    func didSelectSectionHeader(withTag tag: Int) {
        // FORK: discover stripped
        appDelegate.feedDetailViewController.cancelMarkStoryReadTimer()

        currentRowAtIndexPath = nil
        currentSection = tag
        lastRowAtIndexPath = nil
        lastSection = tag

        var folder = (tag >= 0 && tag < foldersArray.count
                      ? foldersArray[tag] as? String : nil) ?? ""

        if tag >= 0 && tag < Self.topSectionNames.count {
            folder = Self.topSectionNames[tag]
        } else if folder != "river_global", folder != "river_blurblogs", !folder.hasPrefix("trending:") {
            folder = "\(tag)"
        }

        clearDashboard()

        if folder == "dashboard" {
            appDelegate.detailViewController.storyTitlesInDashboard = true
            // FORK: dashboard rivers stripped; loadDashboard is a no-op.
            loadDashboard()
        } else {
            appDelegate.feedDetailViewController.beginExplicitFeedSelection()
            appDelegate.loadRiverFeedDetailView(appDelegate.feedDetailViewController, withFolder: folder)
        }

        if !appDelegate.detailViewController.isPhoneOrCompact {
            appDelegate.feedDetailViewController.viewWillAppear(false)
            appDelegate.feedDetailViewController.viewDidAppear(false)
        }
    }

    @objc func clearDashboard() {
        appDelegate.feedDetailViewController.dashboardIndex = -1
        appDelegate.feedDetailViewController.dashboardSingleMode = false
        appDelegate.detailViewController.storyTitlesInDashboard = false
    }

    /// FORK: dashboard rivers stripped — selection is unreachable but the
    /// methods stay so call sites keep compiling.
    @objc func loadDashboard() {}

    @objc func reloadDashboard() {}

    @objc func reloadOneDash(with dashIndex: Int) {}

    // MARK: - Next-unread navigation

    @objc func selectNextFolderOrFeed() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.selectNextUnreadFolderOrFeed()
        }
    }

    @objc func selectNextUnreadFolderOrFeed() -> Bool {
        guard let target = nextUnreadNavigationTarget() else { return false }
        let type = target["type"] as? String

        if type == "feed" {
            guard let indexPath = target["indexPath"] as? IndexPath else { return false }
            selectFeed(at: indexPath)
            return true
        } else if type == "folder" {
            guard let section = (target["section"] as? NSNumber)?.intValue else { return false }
            didSelectSectionHeader(withTag: section)
            return true
        }

        return false
    }

    @objc func nextUnreadNavigationKind() -> String {
        let type = nextUnreadNavigationTarget()?["type"] as? String
        return type == "folder" ? "folder" : "site"
    }

    @objc func nextUnreadNavigationTitle() -> String? {
        nextUnreadNavigationTarget()?["title"] as? String
    }

    @objc func nextUnreadNavigationIcon() -> UIImage? {
        guard let target = nextUnreadNavigationTarget() else { return nil }
        let type = target["type"] as? String

        if type == "feed" {
            return iconForFeed(at: target["indexPath"] as? IndexPath)
        } else if type == "folder" {
            guard let section = (target["section"] as? NSNumber)?.intValue else { return nil }
            return iconForFolder(atSection: section)
        }

        return nil
    }

    @objc func nextUnreadNavigationTarget() -> [String: Any]? {
        if lastRowAtIndexPath != nil {
            return nextUnreadFeedNavigationTarget()
        } else {
            return nextUnreadFolderNavigationTarget()
        }
    }

    private func nextUnreadFeedNavigationTarget() -> [String: Any]? {
        let indexPaths = allIndexPaths()
        if indexPaths.isEmpty { return nil }

        let currentIndexPath = lastRowAtIndexPath
        let currentIndex = currentIndexPath.flatMap { indexPaths.firstIndex(of: $0) } ?? -1

        for offset in 1...indexPaths.count {
            let nextIndex = (currentIndex + offset) % indexPaths.count
            let indexPath = indexPaths[nextIndex]
            if currentIndexPath != nil && indexPath == currentIndexPath { continue }
            if !feedAtIndexPathHasUnreadForNextNavigation(indexPath) { continue }

            let title = titleForFeed(at: indexPath)
            return ["type": "feed", "indexPath": indexPath, "title": title ?? "Next Site"]
        }

        return nil
    }

    private func nextUnreadFolderNavigationTarget() -> [String: Any]? {
        let sectionCount = folderCount
        if sectionCount <= 0 { return nil }

        var current = lastSection
        if current < 0, let lastRowAtIndexPath {
            current = lastRowAtIndexPath.section
        }
        if current < 0 || current >= sectionCount {
            current = -1
        }

        for offset in 1...sectionCount {
            let section = (current + offset) % sectionCount
            if lastSection >= 0 && section == lastSection { continue }
            if !folderAtSectionHasUnreadForNextNavigation(section) { continue }

            let title = titleForFolder(atSection: section)
            return ["type": "folder", "section": NSNumber(value: section), "title": title ?? "Next Folder"]
        }

        return nil
    }

    private func feedAtIndexPathHasUnreadForNextNavigation(_ indexPath: IndexPath) -> Bool {
        guard indexPath.section >= 0, indexPath.section < foldersArray.count,
              let folderName = foldersArray[indexPath.section] as? String,
              let feedsInFolder = foldersDict[folderName] as? [Any],
              indexPath.row >= 0, indexPath.row < feedsInFolder.count else {
            return false
        }

        if appDelegate.isFolderOrParentCollapsed(folderName) { return false }

        let feedIdStr = appDelegate.feedIdWithoutSearchQuery("\(feedsInFolder[indexPath.row])") ?? ""
        if inactiveFeedsDict[feedIdStr] != nil { return false }
        if let searchFeedIds, !searchFeedIds.contains(feedIdStr) { return false }

        return feedIdHasUnreadForNextNavigation(feedIdStr)
    }

    private func feedIdHasUnreadForNextNavigation(_ feedId: String) -> Bool {
        guard !feedId.isEmpty else { return false }

        if appDelegate.isSavedStoriesIntelligenceMode() {
            return appDelegate.savedStoriesCount(forFeed: feedId) > 0
                || appDelegate.isSavedFeed(feedId)
                || appDelegate.isSavedSearch(feedId)
        }

        return unreadCountsMatchNextNavigation(appDelegate.splitUnreadCount(forFeed: feedId))
    }

    private func folderAtSectionHasUnreadForNextNavigation(_ section: Int) -> Bool {
        guard section >= 0, section < foldersArray.count,
              folderSectionIsVisible(section) else { return false }

        guard let folderName = foldersArray[section] as? String else { return false }
        return unreadCountsMatchNextNavigation(appDelegate.splitUnreadCount(forFolder: folderName))
    }

    /// The visibility half of the old heightForHeaderInSection: — the font
    /// math is gone; this answers "does this folder get a header" as a Bool.
    private func folderSectionIsVisible(_ section: Int) -> Bool {
        let prefs = UserDefaults.standard
        guard let folderName = foldersArray[section] as? String else { return false }

        let visibleFeeds = (visibleFolders[folderName] as? Bool) ?? false
        let exempt = section == Self.sectionDashboard
            || section == Self.sectionDiscoverSites
            || section == Self.sectionInfrequent
            || section == Self.sectionAllStories
            || folderName == "daily_briefing"
            || folderName == "river_global"
            || folderName == "river_blurblogs"
            || folderName.hasPrefix("trending:")
            || folderName == "saved_searches"
            || folderName == "saved_stories"
            || folderName == "read_stories"
            || folderName == "widget_stories"
            || folderName == "try_feed"
        if !visibleFeeds && !exempt { return false }

        if section == Self.sectionDashboard && prefs.string(forKey: "dashboard_layout") == "none" { return false }

        if section == Self.sectionInfrequent && !prefs.bool(forKey: "show_infrequent_site_stories") { return false }

        if folderName == "daily_briefing" && !appDelegate.briefingEnabled { return false }
        if folderName == "river_global" && !prefs.bool(forKey: "show_global_shared_stories") { return false }
        if folderName == "trending:well_read" && !prefs.bool(forKey: "show_widely_read_stories") { return false }
        if folderName == "trending:long_reads" && !prefs.bool(forKey: "show_long_reads") { return false }
        if folderName == "trending:good_reads" && !prefs.bool(forKey: "show_good_reads") { return false }

        for parentName in parentTitles(for: folderName) where appDelegate.isFolderCollapsed(parentName) {
            return false
        }

        return true
    }

    private func unreadCountsMatchNextNavigation(_ counts: UnreadCounts?) -> Bool {
        guard let counts else { return false }

        if appDelegate.selectedIntelligence >= 1 {
            return counts.ps > 0
        } else if viewShowingAllFeeds {
            return counts.ps + counts.nt + counts.ng > 0
        } else {
            return counts.ps + counts.nt > 0
        }
    }

    private func titleForFeed(at indexPath: IndexPath) -> String? {
        guard indexPath.section < foldersArray.count,
              let folderName = foldersArray[indexPath.section] as? String,
              let feedsInFolder = foldersDict[folderName] as? [Any],
              indexPath.row < feedsInFolder.count else { return nil }
        let feedIdStr = appDelegate.feedIdWithoutSearchQuery("\(feedsInFolder[indexPath.row])") ?? ""
        guard let feed = (feedsDict[feedIdStr] ?? socialFeedsDict[feedIdStr]) as? [AnyHashable: Any] else { return nil }
        let title = (feed["feed_title"] ?? feed["username"] ?? feed["title"]) as? String
        return title?.isEmpty == false ? title : nil
    }

    private func titleForFolder(atSection section: Int) -> String? {
        guard let folderName = foldersArray[section] as? String else { return nil }

        switch folderName {
        case "dashboard": return "Dashboard"
        case "daily_briefing": return "Daily Briefing"
        case "infrequent": return "Infrequent Site Stories"
        case "everything": return "All Site Stories"
        case "river_global": return "Global Shared Stories"
        case "trending:well_read": return "Widely Read Stories"
        case "trending:long_reads": return "Long Reads"
        case "trending:good_reads": return "Good Reads"
        case "river_blurblogs": return "All Shared Stories"
        case "saved_stories": return "Saved Stories"
        case "saved_searches": return "Saved Searches"
        case "read_stories": return "Read Stories"
        case "widget_stories": return "Widget Site Stories"
        default: return folderName
        }
    }

    private func iconForFeed(at indexPath: IndexPath?) -> UIImage? {
        guard let indexPath,
              indexPath.section >= 0, indexPath.section < foldersArray.count,
              let folderName = foldersArray[indexPath.section] as? String,
              let feedsInFolder = foldersDict[folderName] as? [Any],
              indexPath.row >= 0, indexPath.row < feedsInFolder.count else { return nil }

        let feedIdStr = appDelegate.feedIdWithoutSearchQuery("\(feedsInFolder[indexPath.row])") ?? ""
        let isSocial = appDelegate.isSocialFeed(feedIdStr)
        let isSaved = appDelegate.isSavedFeed(feedIdStr)

        if !isSocial && !isSaved,
           let customIcon = feedIconsDict[feedIdStr] as? [AnyHashable: Any],
           customIcon["icon_type"] as? String != "none",
           let customFeedIcon = CustomIconRenderer.renderIcon(customIcon, size: CGSize(width: 28, height: 28)) {
            return customFeedIcon
        }

        return appDelegate.getFavicon(feedIdStr, isSocial: isSocial, isSaved: isSaved)
    }

    private func iconForFolder(atSection section: Int) -> UIImage? {
        guard section >= 0, section < foldersArray.count,
              let folderName = foldersArray[section] as? String else { return nil }
        return appDelegate.folderIcon(folderName)
    }

    // MARK: - Keyboard navigation (selectNextFeed: etc.)

    @objc func selectNextFeed(_ sender: Any?) {
        let indexPaths = allIndexPaths()
        var indexPath = lastRowAtIndexPath
        var stopAtIndexPath = indexPath
        var foundNext = false

        repeat {
            foundNext = true

            if indexPath == nil {
                if lastSection < 0 {
                    indexPath = indexPaths.first
                } else {
                    indexPath = IndexPath(row: 0, section: lastSection)
                }
                stopAtIndexPath = indexPath
            } else {
                var index = indexPaths.firstIndex(of: indexPath!) ?? -1
                index += 1
                if index >= indexPaths.count { index = 0 }
                indexPath = indexPaths[index]
            }

            if sender == nil, let indexPath {
                guard indexPath.section < foldersArray.count,
                      let folderName = foldersArray[indexPath.section] as? String,
                      let feeds = foldersDict[folderName] as? [Any],
                      indexPath.row < feeds.count else {
                    foundNext = false
                    continue
                }
                let feedIdStr = "\(feeds[indexPath.row])"
                let isInactive = inactiveFeedsDict[feedIdStr] != nil

                if isInactive || appDelegate.isFolderOrParentCollapsed(folderName) {
                    foundNext = false
                } else {
                    let counts = appDelegate.splitUnreadCount(forFeed: feedIdStr)
                    if (counts?.ps ?? 0) + (counts?.nt ?? 0) + (counts?.ng ?? 0) <= 0 {
                        foundNext = false
                    }
                }
            }
        } while !foundNext && indexPath != stopAtIndexPath

        if let indexPath {
            selectFeed(at: indexPath)
        }
    }

    @objc func selectPreviousFeed(_ sender: Any?) {
        let indexPaths = allIndexPaths()
        var indexPath = lastRowAtIndexPath

        if indexPath == nil {
            indexPath = lastSection < 0 ? indexPaths.first : IndexPath(row: 0, section: lastSection)
        }

        var index = indexPath.flatMap { indexPaths.firstIndex(of: $0) } ?? 0
        index -= 1
        if index < 0 { index = indexPaths.count - 1 }
        guard index >= 0, index < indexPaths.count else { return }

        selectFeed(at: indexPaths[index])
    }

    @objc func selectNextFolder(_ sender: Any?) {
        var section = lastSection
        let stopAtSection = section
        var foundNext = false

        repeat {
            foundNext = true

            section = section < folderCount - 1 ? section + 1 : 0
            guard section >= 0, section < foldersArray.count,
                  let folderName = foldersArray[section] as? String else {
                foundNext = false
                continue
            }
            let counts = appDelegate.splitUnreadCount(forFolder: folderName)
            if (counts?.ps ?? 0) + (counts?.nt ?? 0) <= 0 {
                foundNext = false
            }
        } while !foundNext && section != stopAtSection

        didSelectSectionHeader(withTag: section)
    }

    @objc func selectPreviousFolder(_ sender: Any?) {
        var section = lastSection
        let stopAtSection = section
        var foundNext = false

        repeat {
            foundNext = true

            section = section > 0 ? section - 1 : folderCount - 1
            guard section >= 0, section < foldersArray.count,
                  let folderName = foldersArray[section] as? String else {
                foundNext = false
                continue
            }
            let counts = appDelegate.splitUnreadCount(forFolder: folderName)
            if (counts?.ps ?? 0) + (counts?.nt ?? 0) <= 0 {
                foundNext = false
            }
        } while !foundNext && section != stopAtSection

        didSelectSectionHeader(withTag: section)
    }

    @objc func selectEverything(_ sender: Any?) {
        didSelectSectionHeader(withTag: Self.sectionAllStories)
    }

    @objc func selectFolder(_ folder: String) {
        let tag = foldersArray.index(of: folder)
        if tag != NSNotFound {
            didSelectSectionHeader(withTag: tag)
        }
    }

    @objc func selectFeed(_ feedId: String, inFolder folder: String) {
        let section = foldersArray.index(of: folder)
        guard let feedsInFolder = foldersDict[folder] as? [Any],
              section != NSNotFound else { return }

        for (row, thisFeedId) in feedsInFolder.enumerated() where "\(thisFeedId)" == feedId {
            let indexPath = IndexPath(row: row, section: section)
            expandFolderIfNecessary(folder)
            selectFeed(at: indexPath)
        }
    }

    @objc func selectWidgetStories() {
        let tag = foldersArray.index(of: appDelegate.widgetFolder as Any)
        if tag != NSNotFound {
            didSelectSectionHeader(withTag: tag)
        }
    }

    @objc func selectWidgetSource(_ source: String) -> Bool {
        guard let folders = foldersArray as? [String] else { return false }
        let folder: String
        var site: String?
        if source.hasPrefix("feed:") {
            let id = String(source.dropFirst("feed:".count))
            let path = ClassifierFolderPath.serverPath(forFeed: id, folderOrder: folders,
                                                       folders: (foldersDict as? [String: Any]) ?? [:])
            folder = folders.first { ClassifierFolderPath.serverPath(fromNative: $0) == path } ?? "everything"
            site = id
        } else if source.hasPrefix("folder:") {
            let path = String(source.dropFirst("folder:".count))
            guard let native = folders.first(where: { ClassifierFolderPath.serverPath(fromNative: $0) == path }) else { return false }
            folder = native
        } else {
            guard ["all", "infrequent", "trending:well_read", "trending:long_reads", "trending:good_reads"].contains(source) else { return false }
            folder = source == "all" ? "everything" : source
        }
        guard let section = folders.firstIndex(of: folder) else { return false }
        for ancestor in parentTitles(for: folder).reversed() { expandFolderIfNecessary(ancestor) }
        if let site {
            let ids = ClassifierFolderPath.feedIds(in: foldersDict[folder])
            guard let row = ids.firstIndex(of: site) else { return false }
            let hiddenBySearch = searchFeedIds.map { !$0.contains(site) } ?? false
            let needsReload = hiddenBySearch || !isFeedVisible(site)
            if hiddenBySearch {
                searchFeedIds = nil
                viewController?.searchField?.text = nil
            }
            // FeedsViewController.swift keeps the selected row visible even when the widget opens its last unread story.
            stillVisibleFeeds[site] = IndexPath(row: row, section: section)
            if needsReload {
                calculateFeedLocations()
                reloadFeedTitlesTable()
            }
            selectFeed(site, inFolder: folder)
        } else {
            didSelectSectionHeader(withTag: section)
        }
        return true
    }

    @objc func expandFolderIfNecessary(_ folderName: String) {
        let userPreferences = UserDefaults.standard
        let collapseKey = "folderCollapsed:\(folderName)"

        if userPreferences.bool(forKey: collapseKey) {
            userPreferences.set(false, forKey: collapseKey)
            userPreferences.synchronize()
            appDelegate.collapsedFolders = nil
        }
    }

    @objc func isFeedVisible(_ feedId: Any) -> Bool {
        let feedIdStr = (feedId as? String) ?? "\(feedId)"

        // Try feeds are always visible
        if feedIdStr == appDelegate.tryFeedFeedId { return true }

        let unreadCounts = unreadCountsDict[feedIdStr] as? [AnyHashable: Any]
        let stillVisible = stillVisibleFeeds[feedIdStr]
        if stillVisible == nil && appDelegate.isSavedStoriesIntelligenceMode() {
            return appDelegate.savedStoriesCount(forFeed: feedIdStr) > 0
                || appDelegate.isSavedFeed(feedIdStr)
                || appDelegate.isSavedSearch(feedIdStr)
        } else if stillVisible == nil && appDelegate.isSavedSearch(feedIdStr) {
            return true
        } else if stillVisible == nil
            && appDelegate.selectedIntelligence >= 1
            && (unreadCounts?["ps"] as? Int ?? 0) <= 0 {
            return false
        } else if stillVisible == nil
            && !viewShowingAllFeeds
            && (unreadCounts?["ps"] as? Int ?? 0) <= 0
            && (unreadCounts?["nt"] as? Int ?? 0) <= 0 {
            return false
        } else if stillVisible == nil
            && !viewShowingAllFeeds
            && inactiveFeedsDict[feedIdStr] != nil {
            return false
        }

        return true
    }

    @objc func changeToAllMode() {
        viewController?.intelligenceControl?.selectedSegmentIndex = 0
        UserDefaults.standard.set(-1, forKey: "selectedIntelligence")
        UserDefaults.standard.synchronize()
    }

    @objc func selectIntelligence() {
        guard let intelligenceControl = viewController?.intelligenceControl else { return }
        let selectedSegmentIndex = intelligenceControl.selectedSegmentIndex
        let previousSegmentIndex = viewShowingAllFeeds ? 0 : appDelegate.selectedIntelligence + 1
        if selectedSegmentIndex == previousSegmentIndex { return }

        stillVisibleFeeds = NSMutableDictionary()

        let userPreferences = UserDefaults.standard
        switch selectedSegmentIndex {
        case 0:
            userPreferences.set(-1, forKey: "selectedIntelligence")
            viewShowingAllFeeds = true
            appDelegate.selectedIntelligence = 0
        case 1:
            userPreferences.set(0, forKey: "selectedIntelligence")
            viewShowingAllFeeds = false
            appDelegate.selectedIntelligence = 0
        case 2:
            userPreferences.set(1, forKey: "selectedIntelligence")
            viewShowingAllFeeds = false
            appDelegate.selectedIntelligence = 1
        default:
            userPreferences.set(2, forKey: "selectedIntelligence")
            viewShowingAllFeeds = false
            appDelegate.selectedIntelligence = 2
        }
        userPreferences.synchronize()

        calculateFeedLocations()
        reloadFeedTitlesTable()
        viewController?.updateSidebarButton()
    }

    @objc func calculateFeedLocations() {
        activeFeedLocations = NSMutableDictionary()
        visibleFolders = NSMutableDictionary()

        for case let folderName as String in foldersArray {
            if folderName == "river_global" || folderName.hasPrefix("trending:") { continue }
            guard let folder = foldersDict[folderName] as? [Any] else { continue }
            let feedLocations = NSMutableArray()
            for (index, feedId) in folder.enumerated() where isFeedVisible(feedId) {
                feedLocations.add(NSNumber(value: index))
                if !(visibleFolders[folderName] as? Bool ?? false) {
                    visibleFolders[folderName] = NSNumber(value: true)
                }
            }
            activeFeedLocations[folderName] = feedLocations
        }
    }

    // MARK: - Favicons

    @objc func loadFavicons() {
        let urlString = "\(appDelegate.url ?? "")/reader/favicons"
        appDelegate.get(urlString, parameters: nil as Any?, target: self,
                        success: #selector(saveAndDrawFavicons(_:)),
                        failure: #selector(requestFailed(_:)))
    }

    @objc func loadAvatars() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            for case let feedId as String in self.socialFeedsDict.keys {
                guard let feed = self.socialFeedsDict[feedId] as? [AnyHashable: Any],
                      let photoUrl = feed["photo_url"] as? String,
                      let imageURL = URL(string: photoUrl),
                      let imageData = try? Data(contentsOf: imageURL),
                      var faviconImage = UIImage(data: imageData) else { continue }
                faviconImage = Utilities.roundCorneredImage(faviconImage, radius: 6)
                self.appDelegate.saveFavicon(faviconImage, feedId: feedId)
            }
            DispatchQueue.main.async { [weak self] in
                self?.reloadFeedTitlesTable()
            }
        }
    }

    @objc func saveAndDrawFavicons(_ results: [AnyHashable: Any]) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            for (feedId, faviconObject) in results {
                guard self.feedsDict[feedId] != nil,
                      let favicon = faviconObject as? String, !favicon.isEmpty,
                      let imageData = Data(base64Encoded: favicon, options: .ignoreUnknownCharacters),
                      let faviconImage = UIImage(data: imageData) else { continue }
                self.appDelegate.saveFavicon(faviconImage, feedId: "\(feedId)")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reloadFeedTitlesTable()
                self.loadAvatars()
            }
        }
    }

    @objc func requestFailed(_ error: Error?) {
        NSLog("Error: %@", String(describing: error))
        if let error { viewController?.informError(error) }
    }

    // MARK: - Unread count refresh

    @objc func refreshFeedList() {
        refreshFeedList(nil)
    }

    @objc func refreshFeedList(_ feedId: Any?) {
        let accountGeneration = feedListAccountGeneration
        let urlString: String

        if let feedId {
            urlString = "\(appDelegate.url ?? "")/reader/feed_unread_count?feed_id=\(feedId)"
        } else {
            urlString = "\(appDelegate.url ?? "")/reader/refresh_feeds"
        }

        if feedId == nil {
            appDelegate.cancelOfflineQueue()
            // flushQueuedReadStories's callback delivers on the FMDB queue, so
            // this can arrive off-main.
            DispatchQueue.main.async { RealtimeUpdates.shared.noteFullCountRefresh() }
        }

        appDelegate.get(urlString, parameters: nil as Any?, success: { [weak self] _, responseObject in
            guard let self, accountGeneration == self.feedListAccountGeneration else { return }
            self.finishRefreshingFeedList(responseObject as? [AnyHashable: Any], feedId: feedId as? String)
        }, failure: { [weak self] task, error in
            guard let self, accountGeneration == self.feedListAccountGeneration else { return }
            let statusCode = (task?.response as? HTTPURLResponse)?.statusCode ?? 0

            self.finishRefresh()

            if statusCode == 403 {
                NSLog("Showing login after refresh")
                self.appDelegate.showLogin()
            } else if statusCode == 503 {
                self.viewController?.informError("In maintenance mode")
            } else if statusCode >= 500 {
                self.viewController?.informError("The server barfed!")
            } else {
                self.requestFailed(error)
            }
        })

        DispatchQueue.main.async { [weak self] in
            guard let self, accountGeneration == self.feedListAccountGeneration else { return }
            if feedId == nil {
                self.showCountingNotifier()
            }
        }
    }

    private func dispatchFeedRefreshPublication(_ publication: @escaping () -> Void) {
        DispatchQueue.main.async(execute: publication)
    }

    // FeedsObjCViewController.m applies the counts RealtimeUpdates.swift fetched for the feeds the socket named. It
    // skips the favicon download a full refresh does, and updates blurblog rows, which read dictSocialFeeds.
    @objc func applyRealtimeUnreadCounts(_ results: [AnyHashable: Any]) {
        if let socialCounts = results["social_feeds"] as? [String: Any], !socialCounts.isEmpty {
            let socialFeeds = NSMutableDictionary(dictionary: socialFeedsDict)
            for (socialId, countsObject) in socialCounts {
                guard let counts = countsObject as? [String: Any],
                      var socialFeed = socialFeeds[socialId] as? [String: Any] else { continue }
                for key in ["ps", "nt", "ng"] {
                    if let value = counts[key] { socialFeed[key] = value }
                }
                socialFeeds[socialId] = socialFeed
            }
            appDelegate.dictSocialFeeds = socialFeeds as! [AnyHashable: Any]
        }
        finishRefreshingFeedList(results, feedId: "realtime", loadFavicons: false)
    }

    @objc func finishRefreshingFeedList(_ results: [AnyHashable: Any]?, feedId: String?) {
        finishRefreshingFeedList(results, feedId: feedId, loadFavicons: true)
    }

    func finishRefreshingFeedList(_ results: [AnyHashable: Any]?, feedId: String?, loadFavicons: Bool) {
        guard let results else { return }
        let accountGeneration = feedListAccountGeneration
        let intelligenceLevel = appDelegate.selectedIntelligence
        // FeedsObjCViewController.m computes visibility on snapshots, then publishes on main
        // only if authentication has not replaced the account while this work was queued.
        let previousCounts = NSDictionary(dictionary: unreadCountsDict as! [AnyHashable: Any], copyItems: true)
        let folderNames = (foldersArray.copy() as? [Any]) ?? []
        let folderFeeds = NSDictionary(dictionary: foldersDict, copyItems: true)
        let activeLocations = NSDictionary(dictionary: activeFeedLocations as! [AnyHashable: Any], copyItems: true)

        DispatchQueue.global(qos: .default).async { [weak self] in
            guard let self, accountGeneration == self.feedListAccountGeneration else { return }
            var countUpdates: [String: [String: Any]] = [:]
            var visibleUpdates: [String: IndexPath] = [:]
            let newFeedCounts = (results["feeds"] as? [AnyHashable: Any]) ?? [:]
            for (feed, newFeedCountObject) in newFeedCounts {
                let feedIdStr = "\(feed)"
                guard let unreadCount = previousCounts[feedIdStr] as? [AnyHashable: Any],
                      let newFeedCount = newFeedCountObject as? [AnyHashable: Any] else { continue }

                // Check if a feed goes from visible to hidden, but doesn't disappear.
                let oldPs = (unreadCount["ps"] as? Int) ?? 0
                let oldNt = (unreadCount["nt"] as? Int) ?? 0
                let newPs = (newFeedCount["ps"] as? Int) ?? 0
                let newNt = (newFeedCount["nt"] as? Int) ?? 0
                if (intelligenceLevel > 0 && oldPs > 0 && newPs == 0)
                    || (intelligenceLevel == 0 && (oldPs > 0 || oldNt > 0) && newPs == 0 && newNt == 0) {
                    var indexPath: IndexPath?
                    outer: for (section, folderNameObject) in folderNames.enumerated() {
                        guard let folderName = folderNameObject as? String,
                              let activeFolderFeeds = activeLocations[folderName] as? [Any],
                              let originalFolder = folderFeeds[folderName] as? [Any] else { continue }
                        for (location, originalIndexObject) in activeFolderFeeds.enumerated() {
                            let originalIndex = (originalIndexObject as? NSNumber)?.intValue ?? -1
                            if originalIndex >= 0 && originalIndex < originalFolder.count,
                               ("\(originalFolder[originalIndex])" as NSString).intValue == ("\(feed)" as NSString).intValue {
                                indexPath = IndexPath(row: location, section: section)
                                break outer
                            }
                        }
                    }
                    if let indexPath {
                        visibleUpdates[feedIdStr] = indexPath
                    }
                }
                var update: [String: Any] = [:]
                for key in ["ng", "nt", "ps"] {
                    if let value = newFeedCount[key] { update[key] = value }
                }
                countUpdates[feedIdStr] = update
            }

            let newSocialFeedCounts = (results["social_feeds"] as? [AnyHashable: Any]) ?? [:]
            for (feed, newFeedCountObject) in newSocialFeedCounts {
                let feedIdStr = "\(feed)"
                guard previousCounts[feedIdStr] is [AnyHashable: Any],
                      let newFeedCount = newFeedCountObject as? [AnyHashable: Any] else { continue }
                var update: [String: Any] = [:]
                for key in ["ng", "nt", "ps"] {
                    if let value = newFeedCount[key] { update[key] = value }
                }
                countUpdates[feedIdStr] = update
            }

            // FeedsObjCViewController.m replaces provisional partial-cache counts on disk as well as in the sidebar.
            self.appDelegate.database?.inTransaction { db, _ in
                guard let db, accountGeneration == self.feedListAccountGeneration else { return }
                for (feed, counts) in countUpdates {
                    _ = db.executeUpdate("INSERT OR REPLACE INTO unread_counts (feed_id, ps, nt, ng) VALUES (?, ?, ?, ?)",
                                         withArgumentsIn: [feed, counts["ps"] as Any, counts["nt"] as Any, counts["ng"] as Any])
                }
            }

            self.dispatchFeedRefreshPublication { [weak self] in
                guard let self, accountGeneration == self.feedListAccountGeneration else { return }
                for (feed, update) in countUpdates {
                    guard let unreadCount = (self.unreadCountsDict[feed] as? NSMutableDictionary)?.mutableCopy() as? NSMutableDictionary else { continue }
                    unreadCount.addEntries(from: update)
                    self.unreadCountsDict[feed] = unreadCount
                }
                self.stillVisibleFeeds.addEntries(from: visibleUpdates)
                self.folderCountCacheDict.removeAllObjects()
                self.reloadFeedTitlesTable()
                self.refreshHeaderCounts()
                if feedId == nil {
                    self.appDelegate.startOfflineQueue()
                }
                if loadFavicons { self.loadFavicons() }
            }
        }
    }

    // MARK: - Header counts / badge

    /// FeedsObjCViewController's refreshHeaderCounts reduced to its one live
    /// side effect in the fork: the app icon badge. The header labels live in
    /// the hidden VC's view and nobody sees them.
    @objc func refreshHeaderCounts() {
        if awaitingAuthenticatedFeedList || appDelegate.activeUsername == nil {
            return
        }

        folderCountCacheDict.removeObject(forKey: "everything")

        guard let counts = appDelegate.splitUnreadCount(forFolder: "everything") else { return }

        let appUnreadBadge = UserDefaults.standard.string(forKey: "app_unread_badge")
        if appUnreadBadge == "unread" {
            appDelegate.registerForBadgeNotifications()
            UIApplication.shared.applicationIconBadgeNumber = Int(counts.ps) + Int(counts.nt)
        } else if appUnreadBadge == "focus" {
            appDelegate.registerForBadgeNotifications()
            UIApplication.shared.applicationIconBadgeNumber = Int(counts.ps)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    /// FORK: the feed-titles table is hidden — reload calls are no-ops.
    @objc func reloadFeedTitlesTable() {}

    @objc func refreshVisibleFeedCounts() {}

    @objc func refreshFolderCounts() {}

    @objc func refreshFeedCounts() {
        refreshHeaderCounts()
    }

    @objc func deferredReloadFeedTitlesTable() {
        reloadWorkItem?.cancel()

        let throttleInterval: TimeInterval = 0.5
        let timeSinceLastReload = Date().timeIntervalSince(lastFeedTitlesReloadTime)
        let delay = timeSinceLastReload >= throttleInterval ? 0 : throttleInterval - timeSinceLastReload

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastFeedTitlesReloadTime = Date()
            self.refreshFeedCounts()
        }

        reloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    @objc func redrawFeedCounts(_ feedId: Any) {
        refreshHeaderCounts()
    }

    @objc func redrawUnreadCounts() {
        refreshHeaderCounts()
    }

    // MARK: - Notification story

    @objc func loadNotificationStory() {
        loadWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.appDelegate.backgroundLoadNotificationStory()
        }

        loadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + (isOffline ? .seconds(1) : .milliseconds(200)), execute: workItem)
    }

    // MARK: - Preferences

    @objc func resizePreviewSize() {
        reloadFeedTitlesTable()
        appDelegate.feedDetailViewController.reloadWithSizing()
    }

    @objc func resizeFontSize() {
        appDelegate.fontDescriptorTitleSize = nil
        reloadFeedTitlesTable()
        appDelegate.feedDetailViewController.invalidateFontCache = true
        appDelegate.feedDetailViewController.reloadWithSizing()
    }

    @objc func settingDidChange(_ notification: Notification) {
        var identifier = notification.object as? String
        if identifier == nil {
            identifier = notification.userInfo?.keys.first as? String
        }

        // MenuViewController.m also changes this preference directly, producing a defaults notification without a key.
        if identifier == nil || identifier == "infrequent_stories_per_month" {
            if let limit = UserDefaults.standard.object(forKey: "infrequent_stories_per_month") {
                let defaults = UserDefaults(suiteName: "group.com.newsblur.NewsBlur-Group")
                if !(limit as AnyObject).isEqual(defaults?.object(forKey: "widget:infrequent_stories_per_month")) {
                    defaults?.set(limit, forKey: "widget:infrequent_stories_per_month")
                    appDelegate.storyPagesViewController.reloadWidget()
                }
            }
        }

        // FORK: Listen stripped; story button prefs still sync (Fork/ForkStoryButtons.swift).
        if let identifier, ForkStoryButtons.preferenceDidChange(identifier) { return }

        if identifier == "split_behavior" {
            appDelegate.updateSplitBehavior(true)
        } else if identifier == "feed_list_sort_order" {
            appDelegate.reloadFeedsView(true)
        } else if identifier == "feed_list_font_size" {
            resizeFontSize()
        } else if identifier == appDelegate.storiesCollection.storyTitlesPositionKey {
            appDelegate.detailViewController.updateLayout(reload: true, fetchFeeds: true)
        } else if identifier == "story_titles_style" {
            appDelegate.detailViewController.updateLayout(reload: true, fetchFeeds: true)
        } else if identifier == "story_title_swipe_right" || identifier == "story_title_swipe_left" || identifier == "enable_story_swipes" {
            appDelegate.feedDetailViewController.updateStoryTitleSwipePreference()
        } else if identifier == "feed_title_swipe_right" || identifier == "feed_title_swipe_left" || identifier == "enable_feed_swipes" {
            reloadFeedTitlesTable()
        } else if identifier == "story_clustering" {
            let value = UserDefaults.standard.bool(forKey: "story_clustering") ? "true" : "false"
            saveProfilePreference(withKey: "story_clustering", value: value)
            appDelegate.feedDetailViewController.reload()
        } else if identifier == "cluster_mode" {
            let clusterMode = UserDefaults.standard.string(forKey: "cluster_mode") ?? "related"
            saveProfilePreference(withKey: "cluster_mode", value: clusterMode)
            appDelegate.feedDetailViewController.reload()
        } else if identifier == "story_list_preview_images_size" {
            let preview = UserDefaults.standard.string(forKey: "story_list_preview_images_size")
            let defaults = UserDefaults(suiteName: "group.com.newsblur.NewsBlur-Group")
            defaults?.set(preview, forKey: "widget:preview_images_size")
            appDelegate.storyPagesViewController.reloadWidget()
        }
    }

    @objc func languageDidChange(_ notification: Notification) {
        appDelegate.reloadFeedsView(true)
    }

    // MARK: - PreferencesViewDelegate

    @objc(preferencesButtonTappedWithKey:action:) func preferencesButtonTapped(key: String, action: String) {
        if key == "offline_cache_empty_stories" {
            if appDelegate.clearingOfflineCache { return }
            appDelegate.clearingOfflineCache = true
            appDelegate.cancelOfflineQueue()
            // FeedsObjCViewController.m stores the translated status that PreferencesView.swift shows on the button.
            UserDefaults.standard.set(NBLocalization.text("Deleting..."), forKey: key)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                var success = false
                self.appDelegate.database?.inTransaction { db, rollback in
                    guard let db else { rollback?.pointee = ObjCBool(true); return }
                    success = OfflineCacheCleanup.clearDatabase(db)
                    rollback?.pointee = ObjCBool(!success)
                }
                let databaseCleared = success
                let finishDeletion: (Bool) -> Void = { [weak self] imagesRemoved in
                    guard let self else { return }
                    success = success && imagesRemoved
                    DispatchQueue.main.async {
                        if databaseCleared { self.appDelegate.activeCachedImages.removeAllObjects() }
                        self.appDelegate.clearingOfflineCache = false
                        let message = success ? NBLocalization.text("Cleared all stories and images!") : NBLocalization.text("Could not completely clear the cache. Please try again.")
                        UserDefaults.standard.set(message, forKey: key)
                    }
                }
                if success {
                    self.appDelegate.database?.inDatabase { db in
                        guard let db, let documentsURL = self.appDelegate.documentsURL else { return }
                        let imagesRemoved = OfflineCacheCleanup.removeUnreferencedImages(database: db, directory: documentsURL.appendingPathComponent("story_images") as URL)
                        let compacted = OfflineCacheCleanup.compactDatabase(db, force: true)
                        success = imagesRemoved && compacted
                    }
                    let snapshotsRemoved = StoryFirstPageCache.shared.clearSnapshots()
                    success = success && snapshotsRemoved
                    self.appDelegate.deleteAllCachedImages(completion: finishDeletion)
                } else {
                    finishDeletion(false)
                }
            }
        } else if key == "import_prefs" {
            if let presenter = appDelegate.feedsNavigationController.presentedViewController {
                MainActor.assumeIsolated { ImportExportPreferences.importPreferences(from: presenter) }
            }
        } else if key == "export_prefs" {
            if let presenter = appDelegate.feedsNavigationController.presentedViewController {
                MainActor.assumeIsolated { ImportExportPreferences.exportPreferences(from: presenter) }
            }
        } else if key == "delete_account" {
            appDelegate.feedsNavigationController.dismiss(animated: true) { [weak self] in
                guard let self, let splitViewController = self.appDelegate.splitViewController else { return }
                AccountDeletionController.present(from: splitViewController)
            }
        } else if key == "app_icon" {
            appDelegate.feedsNavigationController.dismiss(animated: true)
        }
    }

    @objc(preferenceValueChangedWithKey:value:) func preferenceValueChanged(key: String, value: Any) {
        let notification = Notification(name: Notification.Name("PreferenceValueChanged"),
                                        object: key,
                                        userInfo: [key: value])
        settingDidChange(notification)
    }

    @objc func preferencesDidDismiss() {
        appDelegate.feedsNavigationController.dismiss(animated: true)
        resizeFontSize()
    }

    @objc func validateWidgetFeeds(forGroupDefaults groupDefaults: UserDefaults?, usingResults results: [AnyHashable: Any]) {
        guard let groupDefaults else { return }
        var feeds = groupDefaults.object(forKey: "widget:feeds_array") as? NSMutableArray

        if feeds == nil {
            feeds = NSMutableArray()

            for (key, object) in (results["feeds"] as? [AnyHashable: Any]) ?? [:] {
                guard let feedObject = object as? [AnyHashable: Any] else { continue }
                let feed = NSMutableDictionary()
                let fade = feedObject["favicon_fade"] as? String
                let color = feedObject["favicon_color"] as? String

                feed["id"] = "\(key)"
                feed["feed_title"] = "\(feedObject["feed_title"] ?? "")"

                if let fade { feed["favicon_fade"] = fade }
                if let color { feed["favicon_color"] = color }

                feeds?.add(feed)
            }

            groupDefaults.set(feeds, forKey: "widget:feeds_array")
        }
    }
}
