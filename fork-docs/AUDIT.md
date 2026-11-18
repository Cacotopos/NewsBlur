# M1 audit — upstream iOS client

Upstream checked: `samuelclay/NewsBlur` `main` @ `211283d6a` (2026-11-17). Audit written 2026-11-18 (Brisbane).

## 1. Project facts

| Item | Finding |
|---|---|
| Path | `clients/ios/` (SPEC guess was right). Upstream has its own `clients/ios/CLAUDE.md`; read it, it's accurate. |
| Project | `NewsBlur.xcodeproj` (no workspace in use). `objectVersion = 70` → **synchronized folder groups supported** (already used for `Releases/`). |
| Scheme | `NewsBlur` (upstream says always use this, not `NewsBlur Alpha`). |
| Targets embedded in the app | Share Extension, Subscribe Extension, Story Notification Service Extension, Widget Extension, Old Widget Extension (5 appex). Plus MacWindowChrome (Catalyst only), tests. |
| Dependencies | No CocoaPods/SPM for the app — vendored in `Other Sources/` (AFNetworking, FMDB, PINCache, …). `Package.swift` is only a macOS test package for pure logic. |
| Deployment target | **iOS 26.0** (all targets). Device family `1,2,6` (iPhone, iPad, Catalyst). |
| Toolchain | Local Xcode 26.3 (17C529), iOS 26.3 sim runtime. Upstream releases with Xcode 27; watch for upstream adopting 27-only APIs. |
| Language | ObjC core + Swift. Upstream rule: new files Swift only. Bridging: `Other Sources/BridgingHeader.h`; Swift→ObjC via `NewsBlur-Swift.h`. |
| Signing | `DEVELOPMENT_TEAM = HR7P97SD72` (NewsBlur's), bundle `com.newsblur.NewsBlur`. |

## 2. Build

Simulator: created **"iPad Pro 11 Fork"** (iPad Pro 11" 4th gen = 834 × 1194 pt, same as your M1; iOS 26.3). The pre-existing 11" 4th-gen sims only had older runtimes, too low for the iOS 26 target.

```
xcodebuild -project clients/ios/NewsBlur.xcodeproj -scheme NewsBlur -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPad Pro 11 Fork' build
```

Result: **BUILD SUCCEEDED** with no source changes (670 warnings, all upstream). Simulator builds use "Sign to Run Locally", so there are no signing issues there. The app installs and launches on the sim to upstream's split layout (signed out). Note: the iPad layout already has a draggable feeds/story divider and floating toolbars.

## 3. Free Personal Team blockers

The main app's `Resources/App.entitlements` asks for things a free team can't provision. Device signing will fail until they're removed for the fork build:

| Entitlement / target | Free team | Action |
|---|---|---|
| `aps-environment` (push) | ✗ | drop |
| iCloud (`icloud-container-identifiers`, `icloud-services`, `ubiquity-container-identifiers`) | ✗ | drop. Check what upstream syncs via iCloud; reading must not depend on it |
| `com.apple.developer.applesignin` | ✗ | drop; log in with username/password |
| `associated-domains` | ✗ | drop (only universal links) |
| `usernotifications.communication` | ✗ (likely) | drop |
| App Groups `group.com.newsblur.NewsBlur-Group` (app + Share, Subscribe, Widget) | doubtful, and the group ID is NewsBlur's anyway | drop it, or rename to your own and test in Xcode |
| 5 embedded extensions | each needs its own App ID; the free limit is 10 App IDs per 7 days, and they share the 3-app slot budget awkwardly | **don't embed** in the fork build |

**Proposal (one hook):** a fork-only `Fork/Fork.xcconfig` set as the base configuration of the `NewsBlur` app target. It sets `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM` (left empty for you to pick in Xcode), and `CODE_SIGN_ENTITLEMENTS = Fork/Fork.entitlements` (empty or near-empty). Embedding extensions is a build phase, not a setting, so dropping them needs a second small pbxproj hook, or a fork-only scheme/target. I'll pick the smaller option in M2 and record it in HOOKS.md. Simulator builds are unaffected either way.

## 4. Code map

All paths relative to `clients/ios/Classes/`. "Churn" = upstream commits touching the file in the last year (`git log --since=1.year`).

| Area | File / symbol | Churn | Notes |
|---|---|---|---|
| Scene / window | `SceneDelegate.swift` `scene(_:willConnectTo:)` → `appDelegate.prepareViewControllers()` (line ~87) | 11 | Storyboard `Resources/MainInterface.storyboard` (16) supplies the root. |
| App wiring | `NewsBlurAppDelegate.m` `-prepareViewControllers` (~1482) | **167** | Casts `window.rootViewController` to `SplitViewController`; pulls feeds nav + detail nav out of it. Everything (modals, alerts, login, premium) presents from `appDelegate.splitViewController`. **Avoid hooking this file.** |
| Root split | `SplitViewController.swift` (UISplitViewController subclass) | 22 | Draggable feeds divider (`split_primary_width` pref), Duo/fold handling, Catalyst chrome. |
| Split delegate | `SplitViewDelegate.swift` | 9 | Collapse/expand display-mode decisions. |
| Split behaviour | `NewsBlurAppDelegate.m` `-updateSplitBehavior:` (~1050–1110) | 167 | Re-sets `preferredDisplayMode`/`SplitBehavior` on layout changes. **Fights any fork override of display mode.** |
| Feed list | `FeedsObjCViewController.m` (5078 lines) + `FeedsViewController.swift` subclass | 113 / 5 | Table of sections = `appDelegate.dictFoldersArray`; top sections `dashboard, discover_sites, daily_briefing, infrequent, everything` (`NewsBlurTopSectionNames`, ~240). Special folders (`river_global`, `river_blurblogs`, `trending:*`, `saved_stories`, `read_stories`, `widget_stories`) are appended in the feeds-loaded handler (~1630–1770). Visibility is decided in `heightForHeaderInSection` (~3240). **Also triggers the initial feed fetch** (`loadOfflineFeeds`, then `/reader/feeds`), so it must stay alive even when hidden. |
| Filter bar | `FeedsObjCViewController.h` `feedViewToolbar`, `intelligenceControl` (UISegmentedControl) | — | All/Unread/Focus/Saved lives here. |
| Profile block | `FeedsObjCViewController.h` `userInfoView`, `userAvatarButton` | — | |
| Story list | `FeedDetailObjCViewController.m` (7801) + `FeedDetailViewController.swift` (SwiftUI cards/grid) | **151** / 31 | Fetch: `fetchFeedDetail:` → `/reader/feed/<id>/?page=N&read_filter=…`; `fetchRiverPage:` → `/reader/river_stories/?f=…&page=N`. Pagination via `storiesCollection.feedPage`. |
| Story state | `StoriesCollection.m` (`appDelegate.storiesCollection`) | 13 | **One active collection app-wide** (`activeFeed`/`activeFolder`, `activeFeedStories`, `activeReadFilter`). The reader pages and marks read through it. |
| Reader container | `DetailViewController.swift` (2502) | 50 | Secondary column. Hosts `feedDetailViewController` (story titles when layout is top/bottom/grid) **and** `storyPagesViewController`. Layout pref `story_titles_position` (`titles_on_left`/top/bottom/list/magazine/grid). |
| Reader | `StoryPagesObjCViewController.m` (95) / `StoryDetailObjCViewController.m` | 95 | Stays untouched per SPEC. |
| Open a story | `NewsBlurAppDelegate.m` `-loadFeed:withStory:animated:` (~2414) | 167 | Resets `storiesCollection`, sets `activeFeed`, enters "finding story" mode, then `presentFeedDetailAfterFeedSelection`, which can push upstream's story list. |
| Data model | `NewsBlurAppDelegate.h`: `dictFolders`, `dictFoldersArray`, `dictFeeds`, `dictActiveFeeds`, `dictSubfolders`, `dictUnreadCounts`; `-isFolderCollapsed:` | 46 | Folder names are flattened paths (`"Parent - Child"`), so "top-level folder" = path without a separator; `dictSubfolders` gives the tree. |
| Offline store | FMDB `appDelegate.database`, `Classes/offline/` | — | Stories are cached per feed. The fork could read inline stories from here first. |
| Theme | `ThemeManager.m` (14), `UIColorFromLightSepiaMediumDarkRGB()`; split's `updateTheme` | 14 | 4 themes (Light/Warm/Medium/Dark), not 3. Use the macro for every fork colour. |

## 5. Existing settings that already hide SPEC items

From `Resources/Settings.bundle/Root~ipad.plist`. The fork can default these off in code without hooks:

| SPEC item | Setting |
|---|---|
| NewsBlur Dashboard | `dashboard_layout = none` |
| Infrequent Site Stories | `show_infrequent_site_stories` |
| Global Shared Stories | `show_global_shared_stories` |
| Widely Read | `show_widely_read_stories` |
| Long Reads / Good Reads | `show_long_reads`, `show_good_reads` |
| Add + Discover Sites, All Site Stories, Read Stories, filter strip, profile block | **no setting** |

**Key point:** in the fork layout, upstream's feed list is **never on screen** (the rail and feed column replace it). M3 "declutter" mostly goes away: we hide upstream's list by not showing it, rather than filtering its rows. What's left is:
- Remove Focus/Saved from *our* segmented control. It's our own control, so no hook.
- Keep upstream's list reachable only when `ForkUI.isEnabled = false`.

I suggest merging M3 into M4/M5.

## 6. Proposed architecture and hook points

**Principle:** don't replace `SplitViewController`. `prepareViewControllers` and ~60 call sites assume it exists and presents modals. Instead, **wrap it**.

`ForkRootViewController` (Swift, `Fork/`) becomes `window.rootViewController`:
- children: `ForkRailViewController` + `ForkFeedColumnViewController` (+ overlay in compact mode)
- child: upstream `SplitViewController`, laid out in the reader frame and forced to `secondaryOnly`, so only `DetailViewController` → story pages shows
- upstream `FeedsViewController` stays loaded off-screen (it drives feed fetching and count updates)

| # | File | Symbol | One-line change | Why |
|---|---|---|---|---|
| H1 | `SceneDelegate.swift` (churn 11) | after `appDelegate.prepareViewControllers()` | `ForkUI.install(in: window, split: appDelegate.splitViewController)` | Re-parents the split into the fork root. Single entry point; `ForkUI.isEnabled == false` → no-op. iPad idiom only. |
| H2 | `SplitViewController.swift` (22) | `preferredDisplayMode`/`viewWillTransition` path, or a `ForkUI` check in `SplitViewDelegate` (9) | early-return / force `.secondaryOnly` when fork owns layout | Stops `updateSplitBehavior:` and the delegate re-showing upstream's feeds column. Exact spot settled in M2 by testing. Ideally solved by overriding in a subclass assigned at H1 time, which needs no hook. |
| H3 | `NewsBlurAppDelegate.m` (167) | `-presentFeedDetailAfterFeedSelection` | `if (ForkUI.handlesFeedSelection) return;` at top | Stops upstream pushing its story list when the fork opens a story via `loadFeed:withStory:`. **Only hook in the high-churn file.** Placed at the top of a short method to survive merges. |
| H4 | `NewsBlur.xcodeproj/project.pbxproj` (166) | app target build configs + Fork synchronized group | base xcconfig = `Fork/Fork.xcconfig`; add `Fork/` as a synchronized root group | Signing/entitlements (section 3) and zero-churn file additions. One-time edit. |
| H5 (maybe) | `project.pbxproj` | app target "Embed Foundation Extensions" | remove extensions from the fork build | Only if xcconfig tricks can't skip embedding. |

Data: read `dictFolders`/`dictFeeds`/`dictUnreadCounts` directly. Refresh on upstream's existing reload points: the fork observes `FeedsViewController` reloads through a notification or KVO from Swift, with no hook if one already exists (to verify in M4).

## 7. Risks and SPEC friction

1. **Single `StoriesCollection` vs. multi-open inline stories (biggest).** The feed column shows stories from several feeds at once, but the reader only pages through one collection.
   - *Option A:* the fork fetches inline stories itself (per feed, `/reader/feed/<id>?read_filter=unread&page=N`). Tapping a story calls `loadFeed:withStory:`. The reader's prev/next then walks **that feed's** stories, not the column's visible order across feeds.
   - *Option B:* load the folder as a river into `storiesCollection` and group its stories by feed in the column. Prev/next follows the river, and marking read stays in sync. But "Show N more" becomes river-paged, not per-feed, so a busy feed hogs pages.
   - **Decided 2026-11-18: A** (user). Inline stories are fetched per feed; tapping one calls `loadFeed:withStory:`; reader prev/next stays within that feed.
2. **Read-state sync.** Upstream marks stories read in `storiesCollection`. With A, the fork's inline rows need to watch for read changes. Unread counts are fine (`dictUnreadCounts`); per-story dots need a check against `storiesCollection` or a refetch.
3. **`updateSplitBehavior:` churn.** Upstream retunes split behaviour often (Duo/fold work in 2026). H2 is the hook most likely to break on merge. The M9 drill will tell.
4. **Compact mode (< 1000 pt).** Upstream collapses the split itself at compact *size class*. Our 1000 pt threshold is wider than the size-class switch on 11" (portrait 834 is regular in full screen, compact in narrow Split View). The fork must drive collapse from width, not size class. Upstream's `isCompact` logic inside `DetailViewController` may still swap reader chrome at compact size class. Needs testing in M7.
5. **Reader header buttons.** In `secondaryOnly`, upstream shows its own sidebar toggle in the reader nav bar, which collides with our compact-mode menu button. Hiding it needs `displayModeButtonVisibility = .never` (settable from the fork, no hook).
6. **4 themes, not 3.** SPEC says light/dark/sepia; upstream also has Medium. We'll cover all four.
7. **Nested subfolders: not verified.** I can't sign in to your account, and the folder tree comes from the server. Either sign in on the simulator once (then I can read `dictSubfolders`), or tell me.
8. **Daily Briefing** (`daily_briefing` top section) isn't in SPEC's removed list or the kept items. Assume it's hidden.
