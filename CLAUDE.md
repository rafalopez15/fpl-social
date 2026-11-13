# fpl-social

SwiftUI iOS app for Fantasy Premier League. It never calls FPL directly: everything goes through **fplAPI** (separate repo) under `/api`. FPL calls players "elements", and the code keeps that name.

Rules for one area load from `.claude/rules/` when you open its files: `ui.md`, `notes.md`, `accounts.md`, `teams.md`, `data.md`, `tests.md`, `ci.md`. How-tos for people are in `README.md`. Decisions and their history are in Linear: the "iOS app: design decisions" doc and each story.

## Build and test

`xcode-select` points at the Command Line Tools, so set `DEVELOPER_DIR` first:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
D="platform=iOS Simulator,name=iPhone 18 Pro"   # xcrun simctl list devices available

xcodebuild test -project FPL.xcodeproj -scheme FPL -destination "$D" -only-testing:FPLTests   # unit
xcodebuild test -project FPL.xcodeproj -scheme FPL -destination "$D" -only-testing:FPLTests/ToastTests   # one suite
TEST_RUNNER_TSAN_OPTIONS=halt_on_error=1 xcodebuild test -project FPL.xcodeproj -scheme FPL -destination "$D" \
  -only-testing:FPLTests -enableThreadSanitizer YES   # as CI runs them
xcodebuild test -project FPL.xcodeproj -scheme FPL -destination "$D" -only-testing:FPLUITests -parallel-testing-enabled NO
swiftlint lint --strict              # or the Docker image in ci.md
```

New files under `FPL/` and `FPLTests/` are picked up automatically: never edit `project.pbxproj` by hand.

## Backend URL

- `FPL_API_BASE_URL` is production for Debug and Release in the repo. **Never commit a preview or local URL.**
- To test an unmerged fplAPI PR, pass its preview on the command line (`FPL_API_BASE_URL=https://fpl-api-git-<branch>-fpl-social.vercel.app/api`) or with `-FPLAPIBaseURL` in the scheme's arguments (Debug only). The app PR's "Before merging" says to merge the backend PR first.
- Error bodies are `{"detail": "..."}`; the client surfaces `detail`.

## Product rules

- **Managers' real names never reach the app.** Don't add one to any model, screen or saved data (why: FPL-45).
- **Signing in is optional.** Never prompt at launch. A feature that needs an account opens `SignInView(reason:)` from the action itself, and signed-out screens show an inline invitation, never an empty or broken state.
- **Ask before adding controls.** The app deliberately has few: no filter sheet, no view toggles.
- **Dark mode only.** No light-mode variants or `preferredColorScheme`.

## Code

- iOS 18 deployment target, iOS 26 SDK: wrap newer APIs in `if #available(iOS 26, *)` with an iOS 18 fallback.
- Swift 6 language mode. View models are `@MainActor`; pure helpers on views are `nonisolated` so tests and models can call them.
- **Every screen calls `.themedScreen()`**, or its last rows sit under the tab bar. Colors come from `Theme`, never literals.
- **Always decode with `JSONDecoder.fplAPI`.** New model fields are optional: the API sends `null` when FPL changes a field.
- **Logging:** `Logger` from `Support/Log.swift`, never `print`. Manager ids need `privacy: .private` (numbers are public by default). Never log note text, team or manager names, emails or credentials.
- **Comments:** one or two lines on what the code can't say (why, a constraint, what nil means). No history: ticket numbers, what was tried or picked go in commits, PRs and Linear.
- Tests use Swift Testing (`@Test`, `#expect`), except UI tests.
- Don't commit the local `// xcode: set sdk=iOS` line in `FPLApp.swift`.

## Git and PRs

- Commit or push only when asked. One branch per Linear story from an up-to-date `main` (Linear's branch name works). Merge with a merge commit, never squash.
- Commits: one logical change each, leaving the app working. Short imperative subject, then a body with what and why.
- PR title `FPL-<n>: <what it does>`. Description:
  1. `Closes FPL-<n>.` or `Part of FPL-<n>.`
  2. One or two sentences on what it does for the user.
  3. `## Changes`: one bullet per real change, with the behaviour, the reason and the files or screens.
  4. `## Testing`: what was checked and how, and plainly what wasn't.
  5. `## Before merging` / `## After merging` only when needed.
- Style: plain sentences. No emoji in headings, bold for emphasis, em dashes, hype ("robust", "seamless", "leverage") or closing summary.
