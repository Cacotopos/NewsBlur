# Upstream merge log

One entry per `git merge upstream/main` into `ipad-ui`. Times are Brisbane (UTC+10).

| Date (Brisbane) | Upstream commit | Conflicts | Hooks re-checked | Build / smoke test | Time taken |
|---|---|---|---|---|---|
| 2026-11-18 | `211283d6a` (branch point, no merge) | — | — | builds | — |
| 2026-11-18 (M5 drill, simulated) | `211283d6a` merged into the fork re-applied on `af6bf2304` (20 Oct; 536 upstream commits, SceneDelegate +178, DetailViewController +23, SplitViewController +47, pbxproj +460) | 2, both trivial: upstream added lines right next to H1 (Catalyst `installMacReaderChrome`) and H2 (Dashboard guard). Resolved by keeping both sides, hook first. `project.pbxproj` merged cleanly. | H1, H2, H4a all present after merge; result byte-identical to `ipad-ui` outside `Fork/` | identical tree to the sim-verified `ipad-ui` build | merge 1 s + resolution ~1 min. Real upstream had nothing new (tip still `211283d6a`), hence the simulation. |
| 2026-11-19 07:01 (M9 drill, real) | `d50a20d1e` (19 upstream commits since `211283d6a`; iOS: StoryDetailObjCViewController.m, StoryPagesObjCViewController.h/.m, 39 iOS files, +846/−52) | 0. Upstream touched StoryPagesObjCViewController.m (H8's file) and StoryDetailObjCViewController.m (H5's file) away from the hooks. | All 10 hooks present (8 `FORK:` markers + H6a/H6b settings in pbxproj) | builds; sim smoke test: wide (rail, Comics, Penny Arcade inline) and compact (menu button, overlay) | ~3 min (07:01–07:04) including build and smoke test; merge itself 2 s |

Lesson from the drill: a hook placed on the line right after a busy upstream call (H1) or as the first line of a method (H2) conflicts whenever upstream adds lines in the same spot, but the resolution is always "keep both". rerere (on in this checkout) replays it next time.
