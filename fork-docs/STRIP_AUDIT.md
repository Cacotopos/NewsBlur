# Reachability audit — strip plan for Cacotopic Edition

Upstream checked: `ipad-ui` @ merge `70429d6f66` (post `iOS_17.1` merge). Written 2026-11-23.

## Method

Symbol-reference graph over `clients/ios/{Classes,Fork,Resources,Other Sources}` (435 files, ~146k lines): every `@interface`/`@implementation`/`class`/`struct`/`enum`/`protocol` name maps to its defining files; each file's text is scanned for those names; BFS from the fork's entry set (`Fork/*`, `SceneDelegate`, `NewsBlurAppDelegate`, `main.m`, `MainInterface`/`AuxInterface` storyboards, `Info.plist`, `Settings.bundle` plists, `LaunchScreen.xib`). ObjC headers and their `.m` share names, so a reference marks both.

Result of pure reachability: **418 live / 17 dead (2,614 lines)** — nearly everything is nominally reachable because `NewsBlurAppDelegate` can present almost any screen from the still-running upstream split. Static reachability alone is the wrong lens: the split is pinned `secondaryOnly` (H2/ForkSplitViewController), so the *meaningful* question is which UI entry points remain visible.

So each cluster below is classified by its **entry points**:

- **entry = dead** → invoked only from off-screen UI (hidden `FeedsObjCViewController` rows/menus) → safe to delete after cutting the caller.
- **entry = reader** → invoked from `StoryDetailObjC`/`DetailViewController`/`StoryPages` toolbar (visible in CE) → strip = delete subsystem + remove the toolbar entry in a live file (new FORK hooks).
- **entry = delegate** → invoked by `NewsBlurAppDelegate` lifecycle/sync paths → runs in CE even with no UI → delete = surgical.

## Tier 1 — delete files + cut entry points (~20k lines)

| Cluster | Files | ~Lines | Entry points | Cut sites |
|---|---|---|---|---|
| Listen audio player | `Classes/Listen/*` (24 files) | 8,694 | reader toolbar via `StoryDetailObjC` (18 refs), `SceneDelegate`, delegate | new FORK hook removing the Listen button + presenter wiring |
| Social graph | `ActivityModule`, `InteractionsModule`, `ActivitiesViewController`, `ActivityCell`, `InteractionCell`, `SmallActivityCell`, `SmallInteractionCell`, `FollowGrid`, `FollowCell`, `FriendsListViewController`, `UserProfileViewController`, `UserTagsViewController`, `NotificationFeedCell`, `NotificationsViewController`, `NBNotifier` | ~3,000 | `StoryDetailObjC` share/activity bar, delegate `showUserProfile`/activities, hidden feeds VC | reader share/train bar trim; delegate profile/activities methods |
| First-run wizard | `FirstTimeUserViewController` (+xib), `FirstTimeUserAddSites` (+xib), `FirstTimeUserAddFriends` (+xib), `FirstTimeUserAddNewsBlur` (+xib) | ~6,300 (incl. 4,400 xib) | delegate post-login only for new accounts | delegate first-run gate; Tom's account never triggers it |
| Add-site / discover flow | `AddSiteViewController`, `AddSiteTableCell`, `AddSiteAutocompleteCell`, `FeedChooserViewController` (+xib+title view), `FeedSubscriptionCoordinator`, `AuthorizeServicesViewController`, `LanguageChooserView`, `FeedSubscriptionURL` | ~2,200 | hidden feeds VC "add site"; delegate open-url subscribe | delegate `addSite`/`subscribe` paths, feed mgmt entries |
| Premium upsell | `PremiumManager`, `PremiumViewController` (+xib) | ~400 | delegate upsell checks, hidden feeds VC | delegate `showPremium*` paths — check Tom's account tier first; paywall triggers must not crash |
| Menu infra | `MenuViewController` (+xib), `MenuTableViewCell`, `MenuSectionHeaderView` | ~700 | only the above strip candidates | dies with callers |
| Mark-read-confirm menu | `MarkReadMenuViewController` | 234 | delegate + `FeedDetailObjC` | optional — keep if CE wants the confirm UI; fork's own mark-all-read bypasses it |

## Tier 2 — strip from live files, keep reduced (~call-site edits only)

| Area | Where | What |
|---|---|---|
| Reader social chrome | `StoryDetailObjCViewController.m` | remove activity/interactions bar items (share-to-NewsBlur, blurblog actions); keep system share sheet (`ShareViewController`) only if wanted |
| Trainer UI | `TrainerView.swift`, `TrainerCapsule.swift`, `StoryTrainer*` | entry from reader train button — delete UI files; **keep** `computeStoryScore` + intelligence fields (unread counting depends on them) |
| Preferences | `PreferencesView.swift` + IASK | already filtered by H10 (`ForkPreferences.filtered`); optionally delete hidden `Settings.bundle` sections later — low value, skip |
| FeedsObjCViewController | `Classes/FeedsObjCViewController.m` (5,078) | **cannot delete** — owns `/reader/feeds` fetch, `dictFolders*`, unread counts, `refreshFeedList` (mark-all-read calls it). Runs headless forever. Candidate later for surgical slimming (rows, sections, profile block, add-site); high effort, saves lines not behavior |
| Notifications badge | `NotificationsViewController` entry in `StoryPages` header | remove the bell/button if present on reader chrome |

## Tier 3 — keep (core CE machinery)

- **Reader stack**: `DetailViewController`, `StoryPagesObjC/ViewController`, `StoryDetailObjC/ViewController`, `FeedDetailObjC/ViewController`, `FeedDetailViewController`, `OriginalStoryViewController`, `FontSettings`/`FontList` — the reader is upstream's and stays.
- **Sync/model**: `NewsBlurAppDelegate`, `StoriesCollection`, `SplitViewController`/`ForkSplitViewController`, `FeedsObjC/ViewController` (headless sync engine), `SplitViewDelegate`, `FeedTableCell`/`FeedDetailTableCell`/`FolderTitleView`/`UnreadCountView`/`StoryTitleAttributedString` (referenced by live lists), `DataUtilities`, `Utilities`.
- **Login**: `LoginViewController`, `OnboardingViewController`, `OnboardingAccountViewController` (H13 branding hooks live here).
- **Infra**: `ThemeManager`, `BaseViewController`, offline cache (`offline/` 923 lines — keep: reader falls back to FMDB-cached stories; verify offline prefetch preference off by default), AFNetworking/FMDB/PINCache/SBJSON/IASK vendored libs, `NBModalPushPopTransition`... wait: `NBModalPushPopTransition`, `NBSafariViewController`, `SwiftUtilities`, `StoryPagesCollectionCell`, `AddSiteTableCell`, `FeedSubscriptionURL`, `ShareViewController~ipad.xib`, `fmdb.m`, `AFNetworkActivityIndicatorManager`, `UIKit+AFNetworking.h`, `BridgingHeader.h`, `LaunchScreenDev.xib` — the 17 file-graph dead (2,614 lines); verify `BridgingHeader.h` (build-configured, not source-referenced) and `Info.plist` before deleting; `fmdb.m` is a demo file — safe.
- **Aux scene**: `AuxSceneDelegate` + `AuxInterface.storyboard` — seeded live; verify no CE window uses it before deleting (multiwindow only).

## Tier 4 — not deletable (kept for merge hygiene)

- `NewsBlurAppDelegate` stays whole — 12 hooks documented; it is the fork's API surface.
- Storyboards/xibs of live screens.
- Extensions (`Share/Subscribe/Widget/Story Notification Service`) — already not embedded (H6b); deleting their *folders* is cosmetic, saves repo size not binary — defer.

## Suggested order

1. **Listen** (8.7k) — biggest win, one entry file. 2. **Social cluster** (~3k) — several small files + two live call sites. 3. **First-run wizard** (6.3k incl. xibs) — one delegate gate. 4. **Add-site flow** (2.2k) — several entries; last because `subscribe_url` handling must not break universal links... CE drops associated-domains anyway. 5. **Premium** — verify Tom's account tier first.

Total Tier-1+: **~20k lines of upstream removed**, build-verified per phase, each a single commit for clean merge math. `upstream` remote stays fetchable; conflicts in deleted files resolve as "take deletion".
