# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this is

FPL is a SwiftUI iOS app for browsing Fantasy Premier League players. It doesn't call FPL directly. It talks to **fplAPI**, a separate FastAPI backend (its own repo) that wraps the FPL API and serves cleaned-up JSON under `/api`. FPL calls players "elements", and the code keeps that name.

Current features: a player list per position, sorting, a max price filter, search, a stats popover per player, and team short names.

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

MVVM with one screen. The Xcode project uses file-system synchronized groups, so new files under `FPL/` or `FPLTests/` are picked up without editing `project.pbxproj`.

```
FPL/
  FPLApp.swift                  App entry, shows ContentView
  Model/
    Element.swift               Player model, Status and Position enums, display helpers, JSONDecoder.fplAPI
    ElementFilter.swift         ElementFilter (max price) and ElementSort (points, price, goals, assists, selected by)
    Team.swift                  Team id, name, short name
  Networking/
    FPLAPIClient.swift          async/await client, maps HTTP errors to APIError
  ViewModel/
    ElementViewModel.swift      @MainActor ObservableObject: loading, search, sort, filter, teams
  Views/
    ContentView.swift           List screen, title menu, toolbar, ElementRow
    FilterView.swift            Sort and price filter sheet
    ElementStatsView.swift      Stats popover content
FPLTests/FPLTests.swift         Swift Testing: decoding and filter tests
```

Data flow: `ContentView` owns an `ElementViewModel` (`@StateObject`). `.task(id: viewModel.position)` calls `fetchElements()` on appear and on every position change. The view model fetches players and, on the first load, teams in parallel. `filteredElements` applies search, the filter and the sort on every read; lists are small (under 300 players per position), so nothing is cached.

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

The UI uses standard iOS components and system styling: no custom colors, fonts or assets.

- **Navigation title** is inline and doubles as the position menu (`.toolbarTitleMenu`). With a large title, iOS only shows the menu after scrolling.
- **Bottom bar** (iOS 26+) holds the filter button just left of the search field, via `ToolbarItem(.bottomBar)`, `ToolbarSpacer` and `DefaultToolbarItem(kind: .search)`. Before iOS 26 the filter button sits top right. The filter icon fills in when a filter is active.
- **Rows**, left to right: an `info.circle` button, `webName` with the team short name in grey caption text, then price (secondary) and the sort stat (semibold) as fixed-width trailing columns so numbers line up. News shows under the name, orange unless the player is available.
- **Right-hand stat follows the sort**: points for points and price, `G` for goals, `A` for assists, a percentage for selected by.
- **Stats popover** uses `.presentationCompactAdaptation(.popover)` so it stays a bubble on iPhone. It shows full name, position, team, ownership, then Season and Advanced stats in a two-column grid. Missing values show as "–".
- **Filter sheet** has Sort (field plus order) and a Max price slider sized to the current position's cheapest and most expensive player. Slider at the top means no limit. Changing position clears the price limit and keeps the sort.
- The row's info button uses `.buttonStyle(.borderless)` so tapping the row doesn't open the popover.

The user prefers fewer controls: a minimum-stats section and a player count were removed from the filter sheet on request. Ask before adding controls.

## Conventions

- Deployment target is iOS 18, built with the iOS 26+ SDK. Wrap newer APIs in `if #available(iOS 26, *)` with an iOS 18 fallback.
- Swift 5 language mode. View models are `@MainActor`.
- Tests use Swift Testing (`@Test`, `#expect`), not XCTest. Decoding tests build variants of the fixture in `ElementDecodingTests` (the API's example response for Raya) rather than separate JSON files.
- Don't commit `.DS_Store`, `xcuserdata` or the local `// xcode: set sdk=iOS` line in `FPLApp.swift`.
