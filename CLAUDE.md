# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this is

FPL is a SwiftUI iOS app for browsing Fantasy Premier League players. It doesn't call FPL directly. It talks to **fplAPI**, a separate FastAPI backend (its own repo) that wraps the FPL API and serves cleaned-up JSON under `/api`. FPL calls players "elements", and the code keeps that name.

Current features: a tab bar (Feed, Players, Notes, Profile), and on the Players tab a player list per position, sorting, search, a stats popover per player, and team short names. Feed, Notes and Profile are placeholders; the backlog for them lives in Linear (team FPL Social, projects Transfer Notes and FPL Social).

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

- The app expects fplAPI at `http://127.0.0.1:5000/api` (`FPLAPIClient.baseURL`). The backend is run with `uvicorn main:app --reload --port=5000`. Its own docs say `fastapi dev main.py`, which uses port 8000; if the app can't connect, check which port the server is on.
- `127.0.0.1` only works in the simulator. A physical device needs the Mac's LAN IP and the server started with `--host 0.0.0.0`.
- macOS AirPlay Receiver also listens on port 5000. With the backend stopped, requests get a 403 from AirPlay instead of a connection error.
- `Info.plist` sets `NSAllowsLocalNetworking` so plain HTTP to localhost is allowed.

Endpoints the app uses:

| Endpoint | Returns | Notes |
|---|---|---|
| `GET /api/elements/position/{1-4}` | `[Element]` | 404 when empty; the client turns that into `[]` |
| `GET /api/teams` | `[Team]` | Loaded once per launch |
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
  Networking/
    FPLAPIClient.swift          async/await client, maps HTTP errors to APIError
  ViewModel/
    ElementViewModel.swift      @MainActor ObservableObject: loading, search, sort, teams
  Views/
    ContentView.swift           Root: AppTab enum, the four tabs in a ZStack, FloodlightsTabBar (opens on Feed)
    Theme.swift                 Floodlights colors, Color(hex:), themedScreen() and themedRow() modifiers
    PlayersView.swift           Players tab: list, title menu, toolbar, ElementRow
    FeedView.swift              Feed tab (placeholder, FPL-15)
    NotesView.swift             Notes tab (placeholder, FPL-14)
    ProfileView.swift           Profile tab (placeholder, FPL-9 / FPL-11)
    ElementStatsView.swift      Stats popover content
FPLTests/FPLTests.swift         Swift Testing: decoding and sort tests
```

Data flow: `PlayersView` owns an `ElementViewModel` (`@StateObject`). `.task(id: viewModel.position)` calls `fetchElements()` on appear and on every position change. The view model fetches players and, on the first load, teams in parallel. `filteredElements` applies search and the sort on every read; lists are small (under 300 players per position), so nothing is cached.

## Model rules

These come from the fplAPI contract. Keep them when touching `Element`:

- Only `id`, `webName`, `team`, `elementType`, `nowCost` and `status` are guaranteed. Every other field is optional because the API sends `null` when FPL changes a field. Don't make new fields non-optional.
- Always decode with `JSONDecoder.fplAPI`. It converts snake_case keys and parses `news_added`, which has fractional seconds that the built-in `.iso8601` strategy rejects.
- Money is in tenths of a million: `nowCost` 62 is £6.2m. Use `element.price` for display.
- `status` decodes unknown codes to `.unknown` instead of failing.
- `team` is the team id (1–20). `teamCode` is a different FPL code; don't use it to look up teams.
- `news` can be `""`. Use `currentNews`, which treats empty as nil.
- `photo` is a filename only. The API doesn't build image URLs yet.

## Loading state

`fetchElements()` numbers each request (`fetchGeneration`) and only the newest one writes state. Its `defer` always clears `isLoading` for the newest request, including on cancellation. Don't go back to checking `Task.isCancelled` and returning early: pull-to-refresh used to swap the list for the full-screen spinner, which cancelled the refresh and left the spinner running forever.

The full-screen spinner shows only when `isLoading && elements.isEmpty`. Refreshing keeps the list on screen with the system spinner. Switching position clears `elements` so the old position's players never show under the new title.

## Design

The app uses the **Floodlights** theme (picked from three directions suggested by the ui-ux-pro-max skill): midnight navy surfaces, one green accent, SF Pro type. It is dark mode only: `UIUserInterfaceStyle` is `Dark` in `Info.plist`, so don't add light-mode variants or `preferredColorScheme` calls.

- **Colors** live in `Theme` (`Theme.swift`): `background` #0F0F23, `surface` #1B1B30 (cards, rows, tab bar, popover), `border` #27273B, `text` #F8FAFC, `secondaryText` #94A3B8, `accent` #22C55E (also `AccentColor` in the asset catalog, so `.tint` and buttons pick it up), `onAccent` for content on green, `warning` #FBBF24 for injury news. All text colors pass 4.5:1. Use `Theme` instead of literal colors.
- **Applying it:** every screen calls `.themedScreen()` (navy background, hides list/form backgrounds) and list or form rows call `.themedRow()`. Sheets set `.presentationBackground(Theme.background)`, popovers `Theme.surface`. The player list uses `.contentMargins(.top, 4, for: .scrollContent)` to remove the grouped style's large top gap. Don't override text with `foregroundStyle(_:_:)` on a container: it turns `ContentUnavailableView` descriptions white. System `.primary`/`.secondary` text is fine on navy.
- **Fonts** stay SF Pro with Dynamic Type text styles. Don't add custom fonts.

- **Navigation title** is inline and doubles as the position menu (`.toolbarTitleMenu`). With a large title, iOS only shows the menu after scrolling.
- **Tab bar** is custom (`FloodlightsTabBar`), not the iOS 26 glass one: the user found the glass selection animation too busy. A navy rounded bar with a solid green pill behind the selected tab; switching is instant with a selection haptic. Tabs live in a `ZStack` (unselected ones hidden with opacity, hit testing and accessibility off) so each keeps its state, and the bar is a `.safeAreaInset(edge: .bottom)` so lists scroll clear of it. It carries `.isTabBar` and `.isSelected` traits for VoiceOver. Feed, Players, Notes, Profile, each with an SF Symbol and a label; keep it at five tabs or fewer and put secondary screens inside a tab's stack. Unbuilt tabs show a `ContentUnavailableView` describing what will appear there.
- **Search and sort** on the Players tab sit at the top, because the tab bar owns the bottom: `.searchable` with `.navigationBarDrawer(displayMode: .always)`, and two buttons top right. The first is a `Menu` with an inline `Picker` listing the sort fields (checkmark on the current one); the second (`arrow.up.arrow.down`) flips high-to-low and low-to-high. There is no filter sheet.
- **Rows**, left to right: an `info.circle` button, `webName` with the team short name in grey caption text, then price (secondary) and the sort stat (semibold) as fixed-width trailing columns so numbers line up. Rows are one line: news is not shown in the row.
- **Flagged players** (`status.isFlagged`: doubtful, injured, suspended, unavailable, not eligible; not `.unknown`) get a `Theme.warning` yellow name and an `exclamationmark.triangle.fill` icon just before it (between the info button and the name), labelled with `status.title` for VoiceOver. The user asked for a "hazard emoji"; the SF Symbol was used instead so it takes the theme color.
- **Right-hand stat follows the sort**: points for points and price, `G` for goals, `A` for assists, a percentage for selected by.
- **Stats popover** uses `.presentationCompactAdaptation(.popover)` so it stays a bubble on iPhone. It shows full name, position, team, ownership, then a news callout (yellow with the hazard icon when flagged, grey otherwise; falls back to the status title when a flagged player has no news, and shows "Updated 3 days ago" from `newsAdded`), then Season and Advanced stats in a two-column grid. Missing values show as "–".
- Changing position keeps the sort field and order.
- The row's info button uses `.buttonStyle(.borderless)` so tapping the row doesn't open the popover.

The user prefers fewer controls: a minimum-stats section, a player count, and then the whole filter sheet with its max price slider were removed on request. Ask before adding controls.

## Conventions

- Deployment target is iOS 18, built with the iOS 26+ SDK. Wrap newer APIs in `if #available(iOS 26, *)` with an iOS 18 fallback.
- Swift 5 language mode. View models are `@MainActor`.
- Tests use Swift Testing (`@Test`, `#expect`), not XCTest. Decoding tests build variants of the fixture in `ElementDecodingTests` (the API's example response for Raya) rather than separate JSON files.
- Don't commit `.DS_Store`, `xcuserdata` or the local `// xcode: set sdk=iOS` line in `FPLApp.swift`.
