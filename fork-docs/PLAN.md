# Plan — milestones and tasks

Status: M0 done (push of `ipad-ui` deferred until asked), M1 reviewed (Option A chosen), M2 done and smoke-tested signed in. M4 done. M5 reviewed and drilled. M3 and M6 done (Split View/Stage Manager dropped). M7 built early (2026-11-18) with Wide full screen. M8 done; M9 done except the device install (2026-11-19). Update this file as work lands. Stop for user review at each ⏸.

## M0 — Repo setup
- [x] Fork `samuelclay/NewsBlur` to the user's GitHub (`gh repo fork samuelclay/NewsBlur --clone=false`).
- [x] `~/Source/NewsBlur` already exists (holds `fork-docs/` and `CLAUDE.local.md`), so **init in place, don't clone**: see CLAUDE_CODE_PROMPT.md for exact commands (partial fetch `--filter=blob:none`).
- [x] Branches per MERGE_STRATEGY.md; `rerere` on; `CLAUDE.local.md` in `.git/info/exclude`.
- [ ] Commit `fork-docs/` on `ipad-ui`; push `ipad-ui` to origin. *(committed; push not done — only on request)*
- **Done when:** `git remote -v` shows origin + upstream, `ipad-ui` checked out, docs committed.

## M1 — Audit ⏸
- [x] Locate the iOS project/workspace, schemes, targets, dependency manager (CocoaPods/SPM), min iOS version.
- [x] Build unmodified app for iPad simulator via `xcodebuild`. Record any signing/capability blockers for a free Personal Team (push, iCloud, app groups, extensions).
- [x] Map: iPad root/split view controller; feed list controller + data source (where Dashboard/Infrequent/All Site/Read/Global Shared/Widely Read/Long Reads/Good Reads rows are built); story list controller; story reader controller; bottom filter bar (All/unread/focus/saved); theme manager; folder/feed data model and unread counts; how story lists are fetched/paginated.
- [x] Check whether upstream already has settings to hide special rows.
- [x] *(none — AUDIT §7.7)* Check whether the user's account has nested subfolders (affects SPEC tree assumption).
- **Output:** `fork-docs/AUDIT.md` — file/symbol map, proposed hook points (each with file + one-line change), risks, estimate of upstream churn per file (`git log --since=1.year --format=%h -- <file> | wc -l`). **Stop for review.**

## M2 — Fork scaffold
- [x] `Fork/` group, `ForkUI.isEnabled` switch, `HOOKS.md`, `MERGE_LOG.md`.
- [x] Single hook that swaps in a fork root controller for iPad when enabled.
- **Done when:** app builds and runs with the switch on (showing upstream UI inside the new root) and off.
  - Verified 2026-11-18 on the iPad Pro 11 Fork sim: builds; launch log confirms the root is installed when on and skipped when off (`-fork_ui_enabled NO`); the login modal presents in both. Signed-in smoke test passed (feeds, story list, reader render under the fork root).

## M3 — Declutter
- [x] Hide special rows and profile block. Done by replacement, not a data-source hook: the fork's rail and feed column (M4/M5) replace upstream's feed list, which stays hidden. Preferences no longer offers the special-row toggles either (H10).
- [x] Filter control reduced to All | Unread (the feed column's segmented control).
  - Checked 2026-11-19 on the sim at cold launch: no special rows, no profile block, All | Unread shown.
- **Done when:** none of the SPEC "Removed from view" items show; All/Unread work.

## M4 — Folder rail
- [x] 1/8 rail: squircles, labels, unread badges, selection, Other (top-level feeds), Settings.
- [x] Unread counts update live. Upstream has **no** count-change notification, so the rail listens for `FinishedLoadingFeedsNotification` and also re-reads counts once a second while wide and active. That's cheap, with no hook; it redraws only on change.
  - Verified 2026-11-18 on the sim (landscape 1194 pt):
    - 7 folders + Other + Settings fit without scrolling.
    - Tapping Comics selects it and loads its river in upstream's list.
    - The badge dropped 88 → 87 when the opened story was marked read.
    - The gear opens Preferences.
    - The rail re-themes in dark mode.
  - Decisions taken:
    - Muted feeds count as folder members, so The Oatmeal shows under Other, but they add 0 to badges.
    - Empty folders are hidden.
    - The gear opens upstream's Preferences directly: its settings menu is anchored to the feed-list toolbar, which the fork will hide.
    - Interim until M5: tapping a folder loads its river into upstream's story list. Other is select-only.

## M5 — Feed column ⏸
- [x] Folder header + All/Unread segmented control.
- [x] Collapsible feed rows, multi-open, inline stories, "Show N more" pagination, selection → reader (`loadFeed:withStory:`; H3 not needed).
- [x] Dimmed zero-unread feeds; >3 collapse into one group row.
  - Verified on the sim (landscape): Comics → Oglaf expands to its 4 unread inline; tapping "Freshwater" opens it in the reader, highlights the row, Oglaf 4→3 and Comics badge 86→85. Upstream's feed list and story titles stay hidden.
  - Feed order is frozen when a folder opens (rows don't jump as feeds hit 0). Stories read this session stay visible, dimmed, until the filter or folder changes.
- [x] **M9-style merge drill** run and logged (simulated over 4 weeks of upstream; 2 trivial conflicts, ~1 min). Stop for review.
  - Fixed after review: stories past page 1 never opened (now looked up by hash); rail badge shows feeds/stories.

## M6 — Wide layout
- [x] Rail fixed 88 pt (user: 1/8 wasted space) · feed column 2/8 · reader the rest, at window width ≥ 1000 pt. Done in M5.
- [x] Rotation transitions back to wide re-hide upstream's columns and dock the fork's (sim, 11" portrait ↔ landscape).
- [~] Split View / Stage Manager: won't do. The user doesn't use either (2026-11-19).

## M7 — Compact layout
- [x] < 1000 pt: full-width reader, top-left menu button, full overlay of rail + feed column, story pick closes it. Built 2026-11-18 together with Wide full screen (hooks H7–H9): the reader's full-screen button switches Wide into the same reader-only layout, and the sidebar button became the menu button.
  - Verified on the sim: landscape full screen on/off, overlay panel + dim + story pick closes it; portrait full-screen overlay with close button; rotation both ways.
- [~] Split View / Stage Manager (compact size class): won't do, as in M6.
- [ ] Launch straight into portrait opens the overlay automatically: written, not yet seen on the sim.

## Preferences trim (2026-11-19, user request)
- [x] Preferences hides settings the fork replaces (hook H10). Story order and "Feed and story list" text size now drive the feed column instead of being hidden.
  - Verified on the sim: Story List shows only Story order and Mark stories read; Story Layout and Feed List are gone; Extra Large enlarges feed and story rows; Oldest first lists Penny Arcade 24 → 28 Oct.

## Cacotopic Edition branding (2026-11-19, user request)
- [x] New app icon: eclipse over a horizon on dark navy, with dark and tinted versions (user picked concept B + A's horizon). Replaces upstream's orange sun as the primary icon (hook H11).
- [x] Start-up screen: the mark, "NewsBlur Reader" and "Cacotopic Edition" in Century Gothic on 0x0B0D12 (`Fork/ForkLaunchScreen.storyboard`).
  - Verified on the sim: home-screen icon and cold-launch screen.
- [x] Respaced after review: smaller sun, finer horizon lines with an 82-unit gap, main line at 80% so it no longer outshines the ring, mark centred in the icon (user picked "Finer lines" + 80%).

## M8 — Folder icon picker
- [x] Long-press menu: Initials / Symbol… / First Feed's Icon; SF Symbol picker (curated ~150 topic symbols with search, user choice 2026-11-19); per folder in UserDefaults (`Fork/ForkFolderAppearance.swift`). No upstream hooks.
- [x] Disambiguate colliding short labels: distinct icons, plus Rename Label… / Reset Label in the same menu (user choice 2026-11-19). Initials follow the custom label.
  - Verified on the sim: Comics → theatre masks via search "theater"; News - Technology → first feed's favicon and label "Tech News".

## M9 — Merge drill & polish ⏸
- [x] Merge latest upstream, log conflicts/time in MERGE_LOG.md. 2026-11-19: `d50a20d1e`, 19 commits, no conflicts, all hooks intact, wide + compact smoke test passed.
- [x] Theme check: light, sepia, medium and dark all checked on the sim (2026-11-19); rail, squircles, badges and feed column follow each.
- [x] Dynamic Type: the feed column follows "Use system size" (via H10's list text size); rail labels stay fixed on purpose so they fit 88 pt.
- [x] VoiceOver labels: rail buttons (folder, unread count, selected), feed rows (name, unread, expanded/collapsed, hint), story rows (title, unread, date), menu and close buttons, symbol picker. Not yet walked through with VoiceOver running.
- [x] Signing for a free Personal Team (hooks H6a/H6b, 2026-11-18): unsigned device build succeeds with no extensions embedded.
- [x] Install on the user's iPad Pro 11" (user does signing in Xcode). Installed 2026-11-19 as `com.cacotopos.newsblur-ipad` (iPad Pro 11" 3rd gen, iPadOS 26.6.2). Needed hook H6c (no In-App Purchase, StoreKit not in the link list) for the Personal Team. Lost on device: push, share/subscribe extensions, widgets, Sign in with Apple, universal links, iCloud. Free-team installs expire after 7 days.
