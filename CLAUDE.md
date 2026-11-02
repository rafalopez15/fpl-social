# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this is

FPL is a SwiftUI iOS app for browsing Fantasy Premier League players. It doesn't call FPL directly. It talks to **fplAPI**, a separate FastAPI backend (its own repo) that wraps the FPL API and serves cleaned-up JSON under `/api`. FPL calls players "elements", and the code keeps that name.

Current features: a tab bar (Feed, Players, Notes, Profile), and on the Players tab a player list per position, sorting, search, a stats popover per player, and team short names. Notes lets you write notes tagged with the gameweek (stored on the device). Feed and Profile are placeholders; the backlog for them lives in Linear (team FPL Social, projects Transfer Notes and FPL Social).

## Build and test

Xcode lives at `/Applications/Xcode.app`, but `xcode-select` points at the Command Line Tools, so prefix commands with `DEVELOPER_DIR`:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Unit tests (fast, no backend needed)
xcodebuild test -project FPL.xcodeproj -scheme FPL \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:FPLTests

# Build only
xcodebuild build -project FPL.xcodeproj -scheme FPL \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

Use `xcrun simctl list devices available` if that simulator name doesn't exist. Run `FPLTests` only; `FPLUITests` holds the Xcode template and isn't maintained.

CI (`.github/workflows/swift.yml`) runs the same unit tests on `macos-26` with the latest stable Xcode, triggered by changes under `FPL/`, `FPLTests/`, `FPL.xcodeproj/` or the workflow itself.

## Backend

- The app uses the production fplAPI at `https://fpl-api-six.vercel.app/api` (`FPLAPIClient.baseURL`), deployed on Vercel with the same responses as local. The first request after a few idle minutes can take 1–2 seconds while Vercel starts an instance.
- To work against a local backend, set `baseURL` to `http://127.0.0.1:5000/api` and run it with `uvicorn main:app --reload --port=5000` (its docs say `fastapi dev main.py`, which uses port 8000). `127.0.0.1` only works in the simulator; a physical device needs the Mac's LAN IP and `--host 0.0.0.0`. macOS AirPlay Receiver also listens on port 5000, so with the backend stopped requests get a 403 instead of a connection error.
- `Info.plist` sets `NSAllowsLocalNetworking` so plain HTTP to a local backend is allowed. Production is HTTPS and doesn't need it.

Endpoints the app uses:

| Endpoint | Returns | Notes |
|---|---|---|
| `GET /api/elements/position/{1-4}` | `[Element]` | 404 when empty; the client turns that into `[]` |
| `GET /api/teams` | `[Team]` | Loaded once per launch |
| `GET /api/fixtures?started=false` | `[Fixture]` | Matches still to be played, by kickoff. Loaded once per launch |
| `GET /api/events` | `[Event]` | Gameweeks; `is_next` picks where upcoming fixtures start. Loaded with fixtures |
| `GET /api/elements`, `GET /api/elements/{id}` | `[Element]`, `Element` | Wrapped in the client, not used by the UI yet |

The backend returns `503 {"detail": "FPL data is currently unavailable"}` before it has loaded FPL data. Error bodies are `{"detail": "..."}` and the client surfaces `detail` as the error message.

## Architecture

MVVM. Four tabs, each owning its own `NavigationStack`, switched by a custom tab bar (see Design). The Xcode project uses file-system synchronized groups, so new files under `FPL/` or `FPLTests/` are picked up without editing `project.pbxproj`.

```
FPL/
  FPLApp.swift                  App entry, shows ContentView
  Model/
    Element.swift               Player model, Status and Position enums, display helpers, JSONDecoder.fplAPI
    ElementSort.swift           ElementSort (points, price, goals, assists, selected by)
    Team.swift                  Team id, name, short name
    Fixture.swift               Fixture, Event, FixtureSchedule (a team's next gameweeks)
    Note.swift                  SwiftData Note, NotePlayer, NoteSection (grouping by gameweek)
  Networking/
    FPLAPIClient.swift          async/await client, maps HTTP errors to APIError
  ViewModel/
    ElementViewModel.swift      @MainActor ObservableObject: loading, search, sort, teams
    GameweekStore.swift         Gameweeks and the current one, shared via environment (note tags, deadlines)
  Views/
    ContentView.swift           Root: AppTab enum, the four tabs in a ZStack, FloodlightsTabBar (opens on Feed)
    Theme.swift                 Floodlights colors, Color(hex:), themedScreen() and themedRow() modifiers
    PlayersView.swift           Players tab: list, title menu, toolbar, ElementRow
    FeedView.swift              Feed tab (placeholder, FPL-15)
    NotesView.swift             Notes tab: every gameweek so far with a + to add, edit, swipe to delete
    NoteEditorView.swift        Sheet to write or edit a note, with linked player chips
    ProfileView.swift           Profile tab (placeholder, FPL-9 / FPL-11)
    ElementStatsView.swift      Stats popover content
FPLTests/FPLTests.swift         Swift Testing: decoding and sort tests
```

Data flow: `PlayersView` owns an `ElementViewModel` (`@StateObject`). `.task(id: viewModel.position)` calls `fetchElements()` on appear and on every position change. The view model fetches players and, until they've loaded, teams and the fixture schedule in parallel. Teams or fixtures failing only hides team names or the popover's fixtures, and they're retried on the next fetch. `filteredElements` applies search and the sort on every read; lists are small (under 300 players per position), so nothing is cached.

## Model rules

These come from the fplAPI contract. Keep them when touching `Element`:

- Only `id`, `webName`, `team`, `elementType`, `nowCost` and `status` are guaranteed. Every other field is optional because the API sends `null` when FPL changes a field. Don't make new fields non-optional.
- Always decode with `JSONDecoder.fplAPI`. It converts snake_case keys and parses `news_added`, which has fractional seconds that the built-in `.iso8601` strategy rejects.
- Money is in tenths of a million: `nowCost` 62 is £6.2m. Use `element.price` for display.
- `status` decodes unknown codes to `.unknown` instead of failing.
- `team` is the team id (1–20). `teamCode` is a different FPL code; don't use it to look up teams.
- `news` can be `""`. Use `currentNews`, which treats empty as nil.
- `canSelect`, `canTransact` and `removed` (`can_select`, `can_transact`, `removed`) are optional booleans. Use `isSelectable` to decide whether to show a player: it's false only when `canSelect` is false or `removed` is true. Status `u` alone doesn't hide anyone.
- `photo` is a filename only. The API doesn't build image URLs yet.

## Notes

Notes (FPL-10) are personal and stored on the device with SwiftData. `ContentView` sets `.modelContainer(for: Note.self)` and shares a `GameweekStore` as an environment object; previews need both (`inMemory: true`). Moving notes to the backend waits for accounts (FPL-11).

- The Notes tab lists every gameweek from the current one (`GameweekStore.current`: `is_current`, or `is_next` before the season) back to 1, newest first. Each gameweek is one card: a list section whose first row is the header (`GameweekHeader`), so swipe to delete, undo and VoiceOver work as in any list. The header shows the title, a green "This week" tag on the current gameweek or a lock on past ones, then "Deadline Sat, Oct 31 · 2 notes" (deadlines from `GameweekStore.events`), and a green `+` (44pt target, labelled "Add note to Gameweek N") that opens the editor for that gameweek. Empty gameweeks are a compact card with a muted title, so gameweeks with notes stand out when scanning. Cards are 12pt apart (`listSectionSpacing`). This card layout was picked over a timeline with a vertical line because it keeps the native list (swipe to delete) and has room for the points and transfer notes FPL-14 and FPL-12 add. The `+` replaced a toolbar compose button and a gameweek menu in the editor, which the user found unintuitive. Until the first note, a hint row at the top says "Tap + on a gameweek…". Notes saved while gameweeks couldn't load go under "No gameweek" at the bottom, with no `+`.
- The list is built from gameweeks, so with no gameweeks and no notes it shows a spinner, then "Couldn't load gameweeks" with Retry (`GameweekStore.didFail`). Storing gameweeks with the user (once accounts exist) may remove this; for now it relies on the API.
- **Notes from past gameweeks are read-only** (`Note.isLocked`): they open with the text, chips without ×, a lock line and only a Done button, so your reasoning at the time can't be rewritten. That includes a note just added to an earlier gameweek; the editor warns "can't be edited after saving" before you save one. Notes from the current gameweek, with no gameweek, or while the current gameweek is unknown stay editable. Swipe to delete works on every note, past ones included, since it's the only fix for a mistake in a locked note. Deleting shows a "Note deleted · Undo" toast above the tab bar for 5 seconds (and a VoiceOver announcement); Undo re-inserts a copy (`DeletedNote`) with the same gameweek, dates, text and players. The user preferred undo over a confirmation alert.
- Linked players are stored as `NotePlayer` (id plus `webName`), so notes show names without loading the player list.
- Notes are written from a gameweek's `+` on the Notes tab, or from the stats popover's `square.and.pencil` button, which writes one for the current gameweek and links that player. The popover closes first and the editor sheet opens from the row in `onChange(of: showingStats)`, because a sheet can't present while the popover is up.
- There's no player picker in the editor yet; players can only be linked from the popover, and unlinked with the chip's ×.

## Loading state

`fetchElements()` numbers each request (`fetchGeneration`) and only the newest one writes state. Its `defer` always clears `isLoading` for the newest request, including on cancellation. Don't go back to checking `Task.isCancelled` and returning early: pull-to-refresh used to swap the list for the full-screen spinner, which cancelled the refresh and left the spinner running forever.

The full-screen spinner shows only when `isLoading && elements.isEmpty`. Refreshing keeps the list on screen with the system spinner. Switching position clears `elements` so the old position's players never show under the new title.

## Design

The app uses the **Floodlights** theme (picked from three directions suggested by the ui-ux-pro-max skill): midnight navy surfaces, one green accent, SF Pro type. It is dark mode only: `UIUserInterfaceStyle` is `Dark` in `Info.plist`, so don't add light-mode variants or `preferredColorScheme` calls.

- **Colors** live in `Theme` (`Theme.swift`): `background` #0F0F23, `surface` #1B1B30 (cards, rows, tab bar, popover), `border` #27273B, `text` #F8FAFC, `secondaryText` #94A3B8, `accent` #22C55E (also `AccentColor` in the asset catalog, so `.tint` and buttons pick it up), `onAccent` for content on green, `warning` #FBBF24 for injury news. All text colors pass 4.5:1. Use `Theme` instead of literal colors.
- **Applying it:** every screen calls `.themedScreen()` (navy background, hides list/form backgrounds) and list or form rows call `.themedRow()`. Sheets set `.presentationBackground(Theme.background)`, popovers `Theme.surface`. The player list uses `.contentMargins(.top, 4, for: .scrollContent)` to remove the grouped style's large top gap. Don't override text with `foregroundStyle(_:_:)` on a container: it turns `ContentUnavailableView` descriptions white. System `.primary`/`.secondary` text is fine on navy.
- **Fonts** stay SF Pro with Dynamic Type text styles. Don't add custom fonts.

- **Navigation title** is inline and doubles as the position menu (`.toolbarTitleMenu`). With a large title, iOS only shows the menu after scrolling.
- **Tab bar** is custom (`FloodlightsTabBar`), not the iOS 26 system one: the user found its glass selection animation too busy. A rounded bar with a solid green pill behind the selected tab. It sits on a soft edge (`SoftEdge`): a blur and navy gradient that start 16pt above the bar (counted in the bar's height, so lists' last rows scroll fully clear of it), so rows fade into navy as they pass under it, matching the scroll edge effect under the search bar. `safeAreaBar` was tried for the system effect but didn't reach the tabs' lists. The bar card is Liquid Glass (`.glassEffect`) on iOS 26 and solid navy with a border on iOS 18; switching is instant with a selection haptic. Tabs live in a `ZStack` (unselected ones hidden with opacity, hit testing and accessibility off) so each keeps its state, and the bar is a `.safeAreaInset(edge: .bottom)` so lists scroll clear of it. It carries `.isTabBar` and `.isSelected` traits for VoiceOver. The bar's `safeAreaInset` doesn't reach lists inside each tab's `NavigationStack` (their safe area reads 0 there), so `ContentView` measures the bar and passes its height as the `tabBarClearance` environment value; `themedScreen()` adds it as a bottom content margin. Any new screen must use `themedScreen()` or its last rows will sit under the bar. Feed, Players, Notes, Profile, each with an SF Symbol and a label; keep it at five tabs or fewer and put secondary screens inside a tab's stack. Unbuilt tabs show a `ContentUnavailableView` describing what will appear there.
- **Search and sort** on the Players tab sit at the top, because the tab bar owns the bottom: `.searchable` with `.navigationBarDrawer(displayMode: .always)`, and two buttons top right. The first is a `Menu` with an inline `Picker` listing the sort fields (checkmark on the current one); the second (`arrow.up.arrow.down`) flips high-to-low and low-to-high. There is no filter sheet.
- **Rows**, left to right: an `info.circle` button, `webName` with the team short name in grey caption text, then price (secondary) and the sort stat (semibold) as fixed-width trailing columns so numbers line up. Rows are one line: news is not shown in the row.
- **Flagged players** (`element.availabilityFlag`) get a colored name and an `exclamationmark.triangle.fill` icon just before it (between the info button and the name), labelled with `availabilityDescription` for VoiceOver. **Yellow** (`Theme.warning`, `.doubtful`): a 1–99% chance of playing next round (FPL uses 25/50/75). **Red** (`Theme.danger` #F87171, `.out`): a 0% chance, which covers injuries with or without a return date and suspensions; news containing "Unknown return date" is always red. With no chance from FPL it falls back to status (`d` yellow; `i`, `s`, `u`, `n` red). The user asked for a "hazard emoji"; the SF Symbol was used instead so it takes the theme color.
- **Players who left the league are hidden** (`element.isSelectable`): hidden when FPL's `can_select` is false or `removed` is true (joined another club, released, not in squad). Missing fields mean the player is shown. Hide them in the app rather than the API, because transfer notes and the feed will still need to show departed players.
- **Right-hand stat follows the sort**: points for points and price, `G` for goals, `A` for assists, a percentage for selected by.
- **Stats popover** uses `.presentationCompactAdaptation(.popover)` so it stays a bubble on iPhone. Sections are 12pt apart with a `Theme.border` hairline between them, and stat labels stay on one line (footnote size). It shows full name, position and team, ownership on its own line, then a news callout (in the flag's yellow or red with the hazard icon when flagged, grey otherwise; falls back to `availabilityDescription` when a flagged player has no news, and shows "Updated 3 days ago" from `newsAdded`), then Fixtures, then Season and Advanced stats in a two-column grid. Missing values show as "–".
- **Fixtures** in the popover cover the next 3 gameweeks (the `is_next` gameweek and the two after it, fewer at the end of the season), one column each: `GW10`, the opponent's short name with (H)/(A), and a 1–5 difficulty chip from the player's side (`team_h_difficulty` at home, `team_a_difficulty` away) colored by `Theme.difficultyColors` (green easy to dark red hard, following FPL). A blank gameweek shows "–" rather than skipping ahead; a double stacks both fixtures. Upcoming means `started == false`, not `finished`, which FPL only sets once bonus points are confirmed. Postponed matches (no `event`) aren't shown. With no schedule (empty list, 503, season over) the section is hidden.
- Changing position keeps the sort field and order.
- The row's info button uses `.buttonStyle(.borderless)` so tapping the row doesn't open the popover.

The user prefers fewer controls: a minimum-stats section, a player count, and then the whole filter sheet with its max price slider were removed on request. Ask before adding controls.

## Pull requests and commits

Shared with the fplAPI repo.

**PR title:** `FPL-<n>: <what the PR does>`, imperative and specific, e.g. `FPL-26: Fixtures endpoint with difficulty ratings`. The issue id links the PR to Linear.

**PR description:**

1. First line: `Closes FPL-<n>.` if the PR finishes the ticket, or `Part of FPL-<n>.` if the ticket has work left (e.g. a backend half). "Closes" makes Linear mark the ticket Done on merge.
2. One or two sentences on what the PR does for the user or app, not how.
3. `## Changes`: short bullets, one per real change, each giving the specific behavior and the reason, and naming the files, fields or screens involved. No bullet should fit an unrelated PR unchanged.
4. `## Testing`: what was checked and how (tests, simulator or device runs, which screens and cases). Say plainly what wasn't checked yet.
5. Extra sections only when needed: `## Breaking change`, `## Before merging`, `## After merging`.

**Style:** plain, direct sentences. No emoji in headings, no bold for emphasis, no em dashes. No filler or hype ("robust", "seamless", "leverage", "streamline", "This PR introduces..."). Concrete facts over adjectives: numbers, field names, endpoint paths, before/after behavior. No closing summary paragraph. No AI attribution anywhere, in PRs or commits: no "Generated with Claude Code", no Co-Authored-By lines.

**Commits:** one logical change per commit, each leaving the app working. Short imperative subject, then a body explaining what changed and why.

**Branches and merging:** start each story on a fresh branch from an up-to-date `main`, named with the issue id (Linear's branch name works). Merge PRs with a merge commit, not squash.

## Conventions

- Deployment target is iOS 18, built with the iOS 26+ SDK. Wrap newer APIs in `if #available(iOS 26, *)` with an iOS 18 fallback.
- Swift 5 language mode. View models are `@MainActor`.
- Tests use Swift Testing (`@Test`, `#expect`), not XCTest. Decoding tests build variants of the fixture in `ElementDecodingTests` (the API's example response for Raya) rather than separate JSON files.
- Don't commit `.DS_Store`, `xcuserdata` or the local `// xcode: set sdk=iOS` line in `FPLApp.swift`.
