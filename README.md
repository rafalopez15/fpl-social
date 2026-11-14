# fpl-social

An iOS app for Fantasy Premier League: link your FPL team, follow the gameweek, and write down why you made each transfer.

The app is growing into a social FPL app: a feed of friends' activity is planned (tracked in Linear under the FPL Social project), and the Feed tab is a placeholder until it lands.

The app reads from [fplAPI](#backend), a FastAPI backend that wraps the official FPL API. Debug and Release builds use the production backend; see [Backend](#backend) to test against a preview.

## Features

- **Tabs** for Profile, Gameweek, Feed and Notes.
- **Link your FPL team** on Profile with your FPL manager ID: its points, rank, squad on a pitch, leagues and the season's transfers. Signing in is optional; it syncs your teams and lets you follow others.
- **Gameweek.** One gameweek's matches by day, with kickoff times and live and final scores. Step between gameweeks with the arrows or the title.
- **All players**, from Profile. Browse by position, sort by points, price, goals, assists or ownership, and search by short or full name. Doubtful, injured and suspended players are flagged.
- **Player stats.** A popover with availability news, next fixtures with FPL's difficulty, and season and expected stats.
- **Notes.** Write notes about who you're watching or holding, from the Notes tab or a player's stats popover. Type @ and part of a name to link a player: the first suggestion is picked with a tap, Return or Tab, linked players show as chips and their mentions are highlighted. Each note is tagged with its gameweek, kept on your device, and synced to your account when you're signed in.
- **Transfer notes.** With your team linked, the app notices new transfers when you open it and asks why you made them.
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

### Signing in on Debug builds

Debug builds sign in with staging's Supabase project. To skip the emailed code, set up the staging test user:

1. In staging's Supabase project, open Authentication > Users > Add user, enter an email (for example `test@fplsocial.dev`) and a strong password, and turn on Auto Confirm User. Don't create it in production.
2. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (gitignored) and fill in `TEST_USER_EMAIL` and `TEST_USER_PASSWORD`. The password can't contain `//`, which xcconfig treats as a comment.
3. Build and run Debug. The sign-in sheet now shows "Sign in as test user" under Send code.

Staging tokens only work against a Vercel preview of the backend, not production. Release builds never include the button.

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
