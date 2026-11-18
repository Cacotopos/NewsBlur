# Hooks into upstream files

Every edit to an upstream file is listed here. Source-code hooks carry `// FORK:`.

Check: `git grep -n "FORK:" -- clients/ios ':!clients/ios/Fork'` must list exactly the source hooks below. The project-file hook can't hold a comment, because Xcode rewrites the file, so check it with `git grep -n "F04C0000000000000000F001" -- clients/ios/NewsBlur.xcodeproj/project.pbxproj`. That should give 4 lines: the group, the main-group child, and one per app target.

Fork-only code lives in `clients/ios/Fork/` and never conflicts on merge.

| ID | File | Symbol | Change | Why | Re-apply if upstream rewrites the area |
|---|---|---|---|---|---|
| H1 | `clients/ios/Classes/SceneDelegate.swift` | `scene(_:willConnectTo:options:)`, right after `appDelegate.prepareViewControllers()` | `ForkUI.install(in: window, split: appDelegate.splitViewController)` | Wraps upstream's split view controller in `ForkRootViewController` on iPad. No-op when `ForkUI.isEnabled` is false, on iPhone or on Catalyst. | Put the call wherever upstream finishes `prepareViewControllers()` (the split must already be `window.rootViewController` and assigned to `appDelegate.splitViewController`). It must run before any modal is presented. |
| H4a | `clients/ios/NewsBlur.xcodeproj/project.pbxproj` | `PBXFileSystemSynchronizedRootGroup` `F04C0000000000000000F001 /* Fork */`; child of the main group `CustomTemplate`; in `fileSystemSynchronizedGroups` of the targets **NewsBlur** and **NewsBlur Alpha** | 8 added lines | Every file in `clients/ios/Fork/` compiles into both apps with no further project edits. Both targets compile `SceneDelegate.swift`, so both need `ForkUI`. | Re-add the group line next to `Releases`, re-add it to `CustomTemplate` children, and add `fileSystemSynchronizedGroups = ( F04C…F001 /* Fork */, );` to both app targets. In Xcode: drag `Fork/` in as a folder (synchronized), with target membership NewsBlur + NewsBlur Alpha. |

## Planned (from AUDIT.md section 6, not yet applied)
- H2: keep the split at `secondaryOnly` when the fork owns the layout (M6).
- H3: early return in `-presentFeedDetailAfterFeedSelection` (M5).
- H4b/H5: signing xcconfig/entitlements and skipping embedded extensions for the Personal Team (before installing on a device).
