# Merge strategy

The fork tracks upstream forever and diverges in UI. Every rule here exists to keep `git merge upstream/<default>` cheap.

## Remotes and branches
- `origin` = user's fork on GitHub. `upstream` = `samuelclay/NewsBlur`.
- `<default>` (upstream's default branch; detect with `git remote show upstream`) is a **clean mirror** of upstream. Never commit to it.
- `ipad-ui` = all fork work. Bring upstream in with **merge, not rebase**: `git fetch upstream && git merge upstream/<default>`.
- `git config rerere.enabled true` — recorded conflict resolutions are replayed.
- Nothing is ever PR'd or pushed upstream.

## Code placement
- All new code lives in a fork-only group/folder (e.g. `clients/ios/Fork/`, adjust to project layout found in the audit). New files never conflict.
- Prefer Swift for new code; bridge to upstream Objective-C via the existing bridging header or a fork-only one.
- Edits to upstream files are **hooks only**: the smallest possible change (one call, one override, one early return), each marked:
  ```
  // FORK: <short reason> — see fork-docs/HOOKS.md
  ```
- Every hook is listed in `fork-docs/HOOKS.md` (file, symbol, why, how to re-apply if upstream rewrites the area). `grep -rn "FORK:"` must match that list.
- **Hide, don't delete.** Filter unwanted rows/buttons at the data-source or visibility level; never remove upstream code, assets or menu items.
- Prefer subclassing/composition and swapping the root/split view controller over editing upstream controllers.
- Keep one switch (`ForkUI.isEnabled`, default on) so the upstream UI can be restored for debugging a bad merge.

## Xcode project file
`project.pbxproj` is the most conflict-prone file. Minimise churn: add one fork group once, keep fork files in it, avoid re-sorting or renaming upstream entries. If the project supports folder references or synchronized groups, use them for `Fork/`.

## Merge routine
1. `git fetch upstream && git merge upstream/<default>` on `ipad-ui`.
2. Resolve conflicts; check every `FORK:` hook still applies.
3. Build for iPad simulator; smoke-test wide + compact modes.
4. Log the merge in `fork-docs/MERGE_LOG.md` (date in Brisbane time, upstream commit, conflicts, time taken).
