# fpl-social

An iOS app for Fantasy Premier League. Browse players by position, sort them, spot injured and suspended players at a glance, and check each player's season and advanced stats.

The app is growing into a social FPL app: transfer notes and a feed of friends' activity are planned (tracked in Linear under the Transfer Notes and FPL Social projects). The Feed, Notes and Profile tabs are placeholders until those land.

The app reads from [fplAPI](#backend), a FastAPI backend that wraps the official FPL API. You need the backend running locally to see any data.

## Features

- **Tabs** for Feed, Players, Notes and Profile. Only Players is built so far.
- **Players by position.** Tap the title to switch between goalkeepers, defenders, midfielders and forwards.
- **Sort** from the top-right menu by points, price, goals, assists or ownership. The arrows button next to it flips between high to low and low to high. The column on the right of each row shows the stat you sorted by.
- **Search** by short name or full name.
- **Flagged players.** Doubtful, injured, suspended and unavailable players have a yellow name with a warning triangle in front of it.
- **Player stats.** The ⓘ button on each row opens a popover with the player's injury or availability news (with when it was last updated), position, team, ownership, fixtures for the next 3 gameweeks with FPL's difficulty ratings, season stats (minutes, goals, assists, clean sheets, bonus, cards and more) and expected stats (xG, xA, xGI, xGC, ICT index).
- **Team short names** (ARS, MCI, LIV) next to each player.
- **Notes.** Write notes about who you're watching or holding, from the Notes tab or from a player's stats popover (which links that player). Each note is tagged with the gameweek and stored on your device.
- **Link your FPL team.** Enter your FPL manager ID on the Profile tab to link your team and see its points and rank. It's saved on your device, no sign-in needed.
- Pull to refresh.

## Design

The app is dark mode only and uses a theme called Floodlights: midnight navy backgrounds, one green accent and the system font, so text still follows the user's text size setting. The colors live in `FPL/Views/Theme.swift`. The tab bar is custom rather than the iOS 26 glass one, so switching tabs is instant.

## Requirements

- Xcode 26 or later (iOS 26 SDK).
- iOS 18 or later.
- An internet connection (the app uses the deployed fplAPI).

## Getting started

### Backend

The app uses the production fplAPI at `https://fpl-api-six.vercel.app/api`, so there's nothing to run locally. The first request after a few idle minutes can take 1–2 seconds while Vercel starts an instance.

To work against a local backend instead, clone the fplAPI repo, start it on port 5000 and set `baseURL` in `FPL/Networking/FPLAPIClient.swift` to `http://127.0.0.1:5000/api`:

```sh
uvicorn main:app --reload --port=5000
```

Check it's up with `curl http://127.0.0.1:5000/api/elements/1`. The interactive docs are at `http://127.0.0.1:5000/docs`.

### App

Open `FPL.xcodeproj` in Xcode, pick an iPhone simulator and run the `FPL` scheme.

With a local backend, `127.0.0.1` won't reach your Mac from a physical iPhone. Start the backend with `--host 0.0.0.0` and point `baseURL` at your Mac's local IP address.

### Troubleshooting

- **"Could not connect to the server"** (local backend): it isn't running, or it's on a different port. `fastapi dev main.py` uses port 8000, not 5000.
- **403 errors with the local backend stopped**: macOS AirPlay Receiver also uses port 5000. Turn it off in System Settings → General → AirDrop & Handoff, or run the backend on another port.
- **"FPL data is currently unavailable"**: the backend started but hasn't loaded FPL data yet. Give it a moment and pull to refresh.

## Tests

Unit tests use Swift Testing and don't need the backend. They cover decoding the player response (including missing and null fields, unknown status codes and dates with fractional seconds) and which players get flagged and how sort values are read.

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
  Model/         Element (player), Team, sort options, JSON decoder setup
  Networking/    FPLAPIClient: async/await calls to fplAPI
  ViewModel/     ElementViewModel: loading, search and sort state
  Views/         Tabs and tab bar, theme, player list, stats popover, placeholder tabs
FPLTests/        Unit tests
```

The app follows MVVM. `ContentView` holds the four tabs and the tab bar. `PlayersView` owns an `ElementViewModel`, which fetches players through `FPLAPIClient` and applies search and sort for the list.

## Backend

fplAPI is a separate repo. The app uses these endpoints:

| Endpoint | Used for |
|---|---|
| `GET /api/elements/position/{1-4}` | Players for one position (1 goalkeeper, 2 defender, 3 midfielder, 4 forward) |
| `GET /api/teams` | Team names and short names |

Prices come back in tenths of a million (`62` is £6.2m), and most player fields can be `null`. See `FPL/Model/Element.swift` for the full model.
