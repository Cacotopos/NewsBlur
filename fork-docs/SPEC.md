# NewsBlur iPad fork — UI spec (locked 2026-11-18)

Personal-use fork of the official NewsBlur iOS app (`samuelclay/NewsBlur`, iOS client under `clients/ios/` — verify path). Goal: replace the iPad layout around the existing reader. **Nothing is ever pushed upstream**; upstream is merged *into* the fork continually (see MERGE_STRATEGY.md).

Interactive design preview: https://claude.ai/artifact/T2ZgttswLXyEU1EPyWkfjo
Local copies of the preview source: `design-preview/*.dc.html` (behaviour reference only — the `renderVals()` logic encodes the rules below; they don't render outside the canvas).
Screenshots: `screenshots/`.

## Target
- **iPad only.** No iPhone work. iPhone code paths stay as upstream ships them.
- Device: **iPad Pro 11" (M1)** — 1194 × 834 pt landscape, 834 × 1194 pt portrait.
- Signing: free Apple Personal Team for now (7-day profiles, 3 sideloaded apps, no push/iCloud capabilities). Paid account (~A$145/yr) may come later. Change bundle ID to the user's own.

## Layout modes
Mode is decided by **window width**, not orientation (covers Split View / Stage Manager):

| Window width | Mode | Layout |
|---|---|---|
| ≥ 1000 pt | **Wide** | Three fixed columns: **1/8 rail · 2/8 feed column · 5/8 reader** (on 11" landscape: 149 / 298 / 746 pt) |
| < 1000 pt | **Compact** | Reader full width. Menu button top-left of the reader header opens the rail + feed column as a **full-screen overlay** (rail 149 pt + feed column fills the rest). Picking a story closes the overlay. Close button in the feed column header. |

Columns are fixed proportions, not user-resizable. If 2/8 proves too cramped in use, the fallback to try is 1/8 · 3/8 · 4/8 — do not change without asking.

## Column 1 — Folder rail (1/8)
- One **squircle** (56 pt, continuous corner radius ≈17 pt) per **top-level folder**, label under it (short name, e.g. "Gaming" for "Blogs - Gaming"), unread-count badge top-right (hidden at 0).
- Selected folder: dark fill / inverted.
- **"Other"** squircle pinned at the bottom of the rail for top-level feeds not in any folder (e.g. "The Oatmeal").
- **Settings** gear at the very bottom → opens upstream's existing settings.
- **Folder icon is per folder, chosen by the user** via long-press context menu:
  1. Initials (default)
  2. Symbol… (SF Symbols picker)
  3. First feed's icon (favicon of the folder's first feed)
  Stored locally on device (UserDefaults keyed by folder path). Not synced.
- Rail scrolls if folders overflow; Other + Settings stay pinned at the bottom.

## Column 2 — Feed column (2/8)
- Header: selected folder's full title + segmented control **All | Unread** (the only two filters; upstream's focus/saved filter buttons are removed from view).
- Body: the folder's feeds as **collapsible rows**: chevron, favicon, name (truncate tail), unread count.
  - **Several feeds can be open at once.**
  - Expanding a feed shows its **stories inline** beneath it: unread dot, title (wraps), time. Paginate with a "Show N more unread" row.
  - Tapping a story opens it in the reader and highlights the row.
  - Stories are fetched **per feed** (decided 2026-11-18, AUDIT §7.1). The reader's prev/next walks the tapped feed's stories, not the column's order across feeds.
- **Unread** mode hides read stories; **All** shows them (dimmed text).
- **Feeds with 0 unread**: always visible but **dimmed**. If a folder has **more than 3** such feeds, they collapse into a single dimmed row "N feeds with nothing unread" that expands to show them.
- Nested subfolders inside a top-level folder: render as collapsible group rows in this column (tree). *Assumption — confirm with user if the audit shows the user has nested folders.*
- Ordering: unread feeds first (upstream's sort order within them), then dimmed feeds.

## Column 3 — Reader (5/8)
- **Upstream story reader unchanged**: Story/Text modes, header (feed name, title, date, author, tags), bottom bar (Text, share, prev/next, Done). Only its container frame changes.
- Optional later (not now): one injected CSS `max-width` rule if line length bothers the user.

## Removed from view (hide, never delete — see merge strategy)
From upstream's feed list (`screenshots/01-current-ipad-circled-unused.png`):
- NewsBlur Dashboard, Add + Discover Sites, Infrequent Site Stories, All Site Stories
- Read Stories, Global Shared Stories, Widely Read Stories, Long Reads, Good Reads
- Bottom filter strip beyond All/Unread; upstream's profile header block in the feed list.
First check whether upstream already has settings to hide any of these.

## Theme
Use upstream's theme colours/managers so light/dark/sepia themes keep working. Design-preview colours are placeholders matching upstream's light theme.

## Out of scope
iPhone, Mac Catalyst, reader redesign, App Store distribution, any server/API changes.
