# Kickoff prompt for Claude Code

Run `claude` from `~/Source/NewsBlur`, then paste:

---

You're continuing a planned project: a personal, iPad-only UI fork of the official NewsBlur iOS app. All decisions are made and written down. Read, in order: `CLAUDE.local.md`, `fork-docs/SPEC.md`, `fork-docs/MERGE_STRATEGY.md`, `fork-docs/PLAN.md`. Screenshots are in `fork-docs/screenshots/`, the design preview source in `fork-docs/design-preview/` (live version: https://claude.ai/artifact/T2ZgttswLXyEU1EPyWkfjo).

Do **M0** now. This folder is not yet a git repo and already contains `fork-docs/` and `CLAUDE.local.md`, so initialise in place instead of cloning:

```
gh repo fork samuelclay/NewsBlur --clone=false        # skip if the fork exists
git init
git remote add origin https://github.com/<my-gh-user>/NewsBlur.git
git remote add upstream https://github.com/samuelclay/NewsBlur.git
git fetch --filter=blob:none upstream
git fetch --filter=blob:none origin
DEFAULT=$(git remote show upstream | sed -n 's/.*HEAD branch: //p')
git checkout -b "$DEFAULT" "origin/$DEFAULT"
git checkout -b ipad-ui
git config rerere.enabled true
echo "CLAUDE.local.md" >> .git/info/exclude
git add fork-docs && git commit -m "Add fork docs"
```

Use `gh api user -q .login` for my GitHub username. Then do **M1 (audit)**: build the unmodified app for an iPad simulator with `xcodebuild`, map the code per PLAN.md M1, and write `fork-docs/AUDIT.md`. Stop after M1 and give me a short summary: hook points proposed, blockers for a free Apple Personal Team, and anything in SPEC.md the code makes hard. Don't change app code before I've reviewed the audit.

---
