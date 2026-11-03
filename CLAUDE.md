# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this is

FPL is a SwiftUI iOS app for browsing Fantasy Premier League players. It doesn't call FPL directly. It talks to **fplAPI**, a separate FastAPI backend (its own repo) that wraps the FPL API and serves cleaned-up JSON under `/api`. FPL calls players "elements", and the code keeps that name.

Current features: a tab bar (Feed, Players, Notes, Profile), and on the Players tab a player list per position, sorting, search, a stats popover per player, and team short names. Notes lets you write notes tagged with the gameweek (stored on the device), and asks why when you make a transfer. Profile links your FPL team by manager ID. Feed is a placeholder; the backlog for them lives in Linear (team FPL Social, projects Transfer Notes and FPL Social).

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
| `GET /api/managers/{id}` | `Manager` | Profile's link flow and linked team. 404 "Manager not found", 503 "FPL is unavailable right now". Called live from FPL, cached up to 60s by Vercel |
| `GET /api/managers/{id}/transfers` | `[Transfer]` | Newest first. `time` has fractional seconds. Checked on launch and on returning to the app for transfer notes; Profile lists them |
| `GET /api/managers/{id}/history` | `ManagerHistory` | Points, overall rank, transfers and hit cost per gameweek, and chips used: Notes' gameweek headers and Profile's free transfers. Only those fields are decoded |
| `GET /api/managers/{id}/picks` | `ManagerPicks` | The squad as of the latest deadline: 15 picks with position, multiplier, captain and vice, the chip and automatic subs, and the gameweek's points. Profile's squad. 404 before the first deadline. Only `element` and `position` are guaranteed |
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
    Manager.swift               Manager (an FPL team from /managers/{id}), LinkedTeam
    Transfer.swift              Transfer (from /managers/{id}/transfers), NoteTransfer saved on a note
    History.swift               ManagerHistory (from /managers/{id}/history), GameweekScore, FreeTransfers
    Picks.swift                 ManagerPicks (from /managers/{id}/picks): starters by position, bench, badges, auto-subs
  Networking/
    FPLAPIClient.swift          async/await client, maps HTTP errors to APIError
  ViewModel/
    ElementViewModel.swift      @MainActor ObservableObject: loading, search, sort, teams
    GameweekStore.swift         Gameweeks and the current one, shared via environment (note tags, deadlines)
    LinkedTeamStore.swift       The linked FPL team, saved in UserDefaults, shared via environment; SquadState
    TeamsAndFixturesStore.swift Teams and upcoming fixtures for screens outside the Players tab (Profile's squad)
    LinkTeamModel.swift         Link flow: digits-only ID, lookup, confirm; LinkError messages
  Views/
    ContentView.swift           Root: AppTab enum, the four tabs in a ZStack, FloodlightsTabBar (opens on Feed)
    Theme.swift                 Floodlights colors, Color(hex:), themedScreen() and themedRow() modifiers
    PlayersView.swift           Players tab: list, title menu, toolbar, ElementRow
    FeedView.swift              Feed tab (placeholder, FPL-15)
    NotesView.swift             Notes tab: every gameweek so far with a + to add, edit, swipe to delete
    NoteEditorView.swift        Sheet to write or edit a note, with linked player chips or the transfer
    TransferPromptView.swift    "N new transfers" sheet asking why, one note per transfer; TransferLine
    ProfileView.swift           Profile tab: link your FPL team, its stats, your squad and the season's transfers
    SquadView.swift             Profile's "Your squad" section, its states, and the list used at accessibility text sizes
    PitchView.swift             The squad on a drawn pitch: player cards, the bench strip, PitchBackground
    ElementStatsView.swift      Stats popover content, and statsPopover(...) which presents it with the note flow
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

- The Notes tab lists every gameweek from the current one (`GameweekStore.current`: `is_current`, or `is_next` before the season) back to 1, newest first. Each gameweek is one card: a list section whose first row is the header (`GameweekHeader`), so swipe to delete, undo and VoiceOver work as in any list. The header shows the title, a green "This week" tag on the current gameweek or a lock on past ones, then "Deadline Sat, Oct 31 · 2 notes" (deadlines from `GameweekStore.events`), and a green `+` (44pt target, labelled "Add note to Gameweek N") that opens the editor for that gameweek. With a team linked, the header's right side shows your points that gameweek over your overall rank (`ManagerHistory.score(for:)`, FPL-14): "56 pts" and "▲ 338K", with a green up or red down arrow for the change since the gameweek before, and a red "−4" before the points when you took a hit. The current gameweek's points are live, so `ContentView` refreshes the history when the app becomes active. Empty gameweeks are a compact card with a muted title, so gameweeks with notes stand out when scanning. Cards are 12pt apart (`listSectionSpacing`). The Notes tab hides its navigation bar (`.toolbar(.hidden, for: .navigationBar)`) so the list starts at the top: the tab bar already says where you are, and iOS still blurs rows scrolling under the status bar. The title is kept for accessibility. This card layout was picked over a timeline with a vertical line because it keeps the native list (swipe to delete) and has room for the points and transfer notes FPL-14 and FPL-12 add. The `+` replaced a toolbar compose button and a gameweek menu in the editor, which the user found unintuitive. Until the first note, a hint row at the top says "Tap + on a gameweek…". Notes saved while gameweeks couldn't load go under "No gameweek" at the bottom, with no `+`.
- The list is built from gameweeks, so with no gameweeks and no notes it shows a spinner, then "Couldn't load gameweeks" with Retry (`GameweekStore.didFail`). Storing gameweeks with the user (once accounts exist) may remove this; for now it relies on the API.
- **Notes from past gameweeks are read-only** (`Note.isLocked`): they open with the text, chips without ×, a lock line and only a Done button, so your reasoning at the time can't be rewritten. That includes a note just added to an earlier gameweek; the editor warns "can't be edited after saving" before you save one. Notes from the current gameweek, with no gameweek, or while the current gameweek is unknown stay editable. Swipe to delete works on every note, past ones included, since it's the only fix for a mistake in a locked note. Deleting shows a "Note deleted · Undo" toast above the tab bar for 5 seconds (and a VoiceOver announcement); Undo re-inserts a copy (`DeletedNote`) with the same gameweek, dates, text and players. The user preferred undo over a confirmation alert.
- Linked players are stored as `NotePlayer` (id plus `webName`), so notes show names without loading the player list.
- Notes are written from a gameweek's `+` on the Notes tab, from a transfer on Profile, or from the stats popover's `square.and.pencil` button, which writes one for the current gameweek and links that player. The popover closes first and the editor sheet opens in `onChange(of:)`, because a sheet can't present while the popover is up. `statsPopover(isPresented:element:...)` (ElementStatsView.swift) wraps the popover, that note flow and the model context, so the Players list and Profile's squad open the same popover; use it for any new place that shows a player.
- There's no player picker in the editor yet; players can only be linked from the popover, and unlinked with the chip's ×.

## Linked FPL team

Profile links your FPL team by manager ID (FPL-30). There are no accounts yet (FPL-11), so the link lives on the device.

- `LinkedTeamStore` (environment object from `ContentView`) saves a `LinkedTeam` (id, team name, manager name) as JSON in UserDefaults under `linkedTeam`, so the link survives relaunches and shows without a network call. `refresh()` fetches points and rank for the card and keeps the saved names if it fails. Transfer notes (FPL-12) read the manager ID from here.
- The link flow (`LinkTeamModel`): a digits-only field (capped at 10 digits; pasting an FPL URL keeps only its digits), "Find team", then an "Is this your team?" card with team name, manager name, points and rank. Nothing is saved until "Link team". "Not my team" goes back to the field with the ID kept.
- Errors show under the field: 404 "No FPL team with that ID" (red, no retry, since retrying won't help), 503 "FPL is down or updating..." and connection failures (yellow, the button becomes "Try again").
- Linked: a card with team, manager name, ID, overall points, overall rank, last gameweek's points, team value and money in the bank (`last_deadline_value`, `last_deadline_bank`: as of the last deadline, so they don't move until the next one), and free transfers. FPL only gives the signed-in manager their free transfers, so `FreeTransfers.available` works them out from `/managers/{id}/history`: 1 after the gameweek you joined, +1 per gameweek minus those used (never below 0), up to 5, a Wildcard or Free Hit keeps what you had without adding 1 (the user confirmed this against their own team), and transfers already made for the next gameweek are taken off. It can't know one-off top-ups FPL announces mid-season (like 2024/25's AFCON boost to 5); if FPL changes the rules, update it there. A `…` menu in the card's corner holds "Change team" (the current link stays until a new team is confirmed; Cancel returns) and "Unlink team" (confirmation dialog). They used to be buttons below the card; the user moved them up so they don't have to scroll past the transfers.
- Below the card, "Transfers" lists the season's transfers from `/managers/{id}/transfers`, one card per gameweek (latest first, `NamedTransfer.byGameweek`), with the date and, when one was written, the transfer note. Tapping a transfer (rows end in a chevron) opens its note, or starts one in `NoteEditorView(gameweek:transfer:)`: a transfer note filed under that transfer's gameweek and dated by it, the same as one from the prompt, so it shows on Notes and in the popover. Notes for past gameweeks lock once saved, as elsewhere; the user chose this. They load with `refresh()`, together with the player names from `/api/elements`, and update when the transfer prompt finds new ones. This list is from the API and covers the whole season; transfer notes only exist for transfers made after linking.
- Between the card and the transfers, "Your squad" (FPL-36, `SquadView.swift`, `PitchView.swift`) shows the squad from `/managers/{id}/picks`: a card headed "Gameweek 9 · 45 pts" with points on the bench underneath and the chip (e.g. "Triple Captain") on the right, then the starting XI on a pitch and the bench on a navy strip below it (labelled GKP, 1, 2, 3, in substitution order). The pitch is drawn with a `Canvas` (`PitchBackground`): a top-down half pitch, goalkeeper at the top and forwards on the halfway line, in muted greens (`Theme.pitch`, `Theme.pitchStripe`) rather than FPL's bright green so it sits in the navy theme; the tilted 3D pitch FPL uses was skipped because it narrows the top rows. Each player card is a grey shirt (`Theme.shirt`; club colors wait for FPL-38, since FPL's kit images are their branded artwork), the name on a navy plate (in the flag's yellow or red when flagged), and the next gameweek's opponent on its difficulty color ("NFO (A)", "NFO +1" for a double, "–" for a blank). Per-player points replace that line once FPL-37 lands. Top left: a green C (TC for a Triple Captain) or navy V. Top right: a green up arrow or red down arrow for automatic subs, otherwise the flag's triangle. FPL's picks already have auto-subs swapped, so the sub shows in the XI and the player he replaced on the bench, keeping a C if he was captain, as on the FPL site. A 5-man line fits on a 402pt iPhone because the pitch runs into the card's padding and names shrink to 70%. Cards open the Players tab's stats popover, below the card when it's in the top half of the visible scroll area and above it otherwise (`onGeometryChange` in `.scrollView` space), so it always has room. At accessibility text sizes the cards can't fit, so the squad shows as a list grouped by position instead (rows with the info icon, name, team, badge and "Subbed in"/"Subbed out"). There's no Pitch/List toggle: the user prefers fewer controls. The user chose the placement above transfers, the popover, the pitch and grey shirts. FPL only publishes picks at the deadline, so a footnote says transfers since then aren't shown yet. `LinkedTeamStore.squad` (`SquadState`) loads with `refresh()`: placeholder rows while loading, "No squad yet" on a 404, "Couldn't load your squad" with Retry on a 503 or other failure; a failed refresh keeps a squad already shown. Names and the popover's stats come from `LinkedTeamStore.players` (`/api/elements`, loaded once and shared with the transfers list); team names and fixtures from `TeamsAndFixturesStore`, retried whenever the squad state changes. Cards don't show each player's gameweek points: `players` isn't reloaded, so `event_points` could be a gameweek old, and there's no live endpoint yet (FPL-37).
- Profile hides its title bar, like Notes.

## Transfer notes

When you make a transfer in FPL, the app asks why (FPL-12). Decisions are on the ticket.

- `LinkedTeamStore.checkForTransfers()` runs on launch, when a team is linked and when the app becomes active (`ContentView`). It fetches `/managers/{id}/transfers`, keeps those made after `transfersSeenUntil` (UserDefaults), resolves names from `/api/elements` and sets `pendingTransfers`. Linking sets `transfersSeenUntil` to now, so the season's earlier transfers are never prompted. FPL doesn't push transfers and Vercel caches for 60s, so a new transfer can take a minute to show.
- `ContentView` shows `TransferPromptView` while `pendingTransfers` isn't empty: one card per transfer (IN with price, OUT, a "Why did you bring in X?" field) and one Save. Later and Save both save a `Note` per transfer, with `transfer` set (`NoteTransfer`: both players, the price paid for the player in, what the player out sold for (`outCost`, FPL's `element_out_cost`, which can be below his price then because FPL keeps half of any rise), time), `gameweek` = the transfer's `event` and `createdAt` = its time, then `finishPrompt()` moves `transfersSeenUntil` past them. Swipe-to-dismiss is disabled so transfers can't be lost.
- A skipped transfer note has empty text. It shows on the Notes tab as "Why did you bring in X? Tap to write it." and stays editable even in a past gameweek until written once (`Note.isLocked` ignores empty text).
- The stats popover shows your latest transfer of the player this season (`Note.latestTransfer`), from `LinkedTeamStore.transferHistory` so it covers transfers made before linking: "Bought in GW9" with the price paid, or "Sold in GW8" with the selling price and who replaced him, then the note from that transfer if there is one ("No note written." for a skipped one). Nothing if he wasn't transferred this season or no team is linked. Before the history has loaded it falls back to transfer notes. `ElementRow` passes the history in. The user wanted this in the popover, not as a tag on the list rows.
- The popover's `@Query` needs `.modelContext(modelContext)` passed from `ElementRow`: popover content didn't inherit the model container and the query came back empty.
- To test the prompt without making real transfers, launch with `-transfersSeenUntil "<date>2026-10-28T00:00:00Z</date>"` (argument-domain UserDefaults) after linking manager 1.

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
