# Plan — milestones and tasks

Status: M0 done (push of `ipad-ui` deferred until asked), M1 reviewed (Option A chosen), M2 done and smoke-tested signed in. M4 done (rail; interim: folder tap loads upstream's river). Next: M5. Update this file as work lands. Stop for user review at each ⏸.

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
- [ ] Hide special rows and profile block (filter at data-source level, one hook).
- [ ] Filter control reduced to All | Unread.
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
- [ ] Folder header + All/Unread segmented control.
- [ ] Collapsible feed rows, multi-open, inline stories, "Show N more" pagination, selection → reader.
- [ ] Dimmed zero-unread feeds; >3 collapse into one group row.
- **Then run M9-style merge drill once** and log it. Stop for review.

## M6 — Wide layout
- [ ] Fixed 1/8 · 2/8 · 5/8 at window width ≥ 1000 pt, reader container = upstream reader.

## M7 — Compact layout
- [ ] < 1000 pt: full-width reader, top-left menu button, full overlay of rail + feed column, story pick closes it. Test portrait, Split View, Stage Manager.

## M8 — Folder icon picker
- [ ] Long-press menu: Initials / Symbol… / First feed's icon; SF Symbol picker; persist per folder in UserDefaults.
- [ ] Disambiguate colliding short labels ("Blogs - Technology" / "News - Technology" both show "Te / Technology") — user chose to solve via distinct icons here (2026-11-18).

## M9 — Merge drill & polish ⏸
- [ ] Merge latest upstream, log conflicts/time in MERGE_LOG.md.
- [ ] Theme check (light/dark/sepia), Dynamic Type sanity, VoiceOver labels on rail/rows.
- [ ] Install on the user's iPad Pro 11" (user does signing in Xcode).
