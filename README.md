# fpl-social

An iOS app for Fantasy Premier League. Browse players by position, sort and filter them, and check each player's season and advanced stats.

The app reads from [fplAPI](#backend), a FastAPI backend that wraps the official FPL API. You need the backend running locally to see any data.

## Features

- **Players by position.** Tap the title to switch between goalkeepers, defenders, midfielders and forwards.
- **Sort** by points, price, goals, assists or ownership, high to low or low to high. The column on the right of each row shows the stat you sorted by.
- **Max price filter** with a slider covering the current position's price range.
- **Search** by short name or full name.
- **Player stats.** The ⓘ button on each row opens a popover with position, team, ownership, season stats (minutes, goals, assists, clean sheets, bonus, cards and more) and expected stats (xG, xA, xGI, xGC, ICT index).
- **Availability news** under the player's name, in orange when the player is doubtful, injured or suspended.
- **Team short names** (ARS, MCI, LIV) next to each player.
- Pull to refresh.

## Requirements

- Xcode 26 or later. The app uses iOS 26 toolbar APIs; on older iOS the filter button moves to the top right.
- iOS 18 or later.
- The fplAPI backend running on your Mac.

## Getting started

### Backend

Clone the fplAPI repo and start it on port 5000:

```sh
uvicorn main:app --reload --port=5000
```

Check it's up with `curl http://127.0.0.1:5000/api/elements/1`. The interactive docs are at `http://127.0.0.1:5000/docs`.

The app looks for the backend at `http://127.0.0.1:5000/api`. To use a different host or port, change `baseURL` in `FPL/Networking/FPLAPIClient.swift`.

### App

Open `FPL.xcodeproj` in Xcode, pick an iPhone simulator and run the `FPL` scheme.

To run on a physical iPhone, `127.0.0.1` won't reach your Mac. Start the backend with `--host 0.0.0.0` and point `baseURL` at your Mac's local IP address.

### Troubleshooting

- **"Could not connect to the server"**: the backend isn't running, or it's on a different port. `fastapi dev main.py` uses port 8000, not 5000.
- **403 errors with the backend stopped**: macOS AirPlay Receiver also uses port 5000. Turn it off in System Settings → General → AirDrop & Handoff, or run the backend on another port.
- **"FPL data is currently unavailable"**: the backend started but hasn't loaded FPL data yet. Give it a moment and pull to refresh.

## Tests

Unit tests use Swift Testing and don't need the backend. They cover decoding the player response (including missing and null fields, unknown status codes and dates with fractional seconds) and the price filter.

Run them in Xcode with ⌘U, or from the command line:

```sh
xcodebuild test -project FPL.xcodeproj -scheme FPL \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:FPLTests
```

Swap in any simulator from `xcrun simctl list devices available`.

GitHub Actions runs the same tests on every push and pull request to `main` that touches the app, tests or project file.

## Project structure

```
FPL/
  Model/         Element (player), Team, sort and filter types, JSON decoder setup
  Networking/    FPLAPIClient: async/await calls to fplAPI
  ViewModel/     ElementViewModel: loading, search, sort and filter state
  Views/         Player list, filter sheet, stats popover
FPLTests/        Unit tests
```

The app follows MVVM. `ContentView` owns an `ElementViewModel`, which fetches players through `FPLAPIClient` and applies search, sort and filters for the list.

## Backend

fplAPI is a separate repo. The app uses these endpoints:

| Endpoint | Used for |
|---|---|
| `GET /api/elements/position/{1-4}` | Players for one position (1 goalkeeper, 2 defender, 3 midfielder, 4 forward) |
| `GET /api/teams` | Team names and short names |

Prices come back in tenths of a million (`62` is £6.2m), and most player fields can be `null`. See `FPL/Model/Element.swift` for the full model.
