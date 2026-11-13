---
paths:
  - "FPL/Networking/FPLAPIClient.swift"
  - "FPL/Model/Element.swift"
  - "FPL/Model/ElementSort.swift"
  - "FPL/Model/Team.swift"
  - "FPL/Model/Fixture.swift"
  - "FPL/ViewModel/ElementViewModel.swift"
  - "FPL/ViewModel/GameweekStore.swift"
  - "FPL/ViewModel/TeamsAndFixturesStore.swift"
  - "FPL/Views/ContentView.swift"
  - "FPL/Support/Log.swift"
  - "FPL/Info.plist"
  - "FPLTests/FPLTests.swift"
  - "FPLTests/RequestCountTests.swift"
---

# Data and networking

## Element

- Only `id`, `webName`, `team`, `elementType`, `nowCost` and `status` are guaranteed; everything else is optional.
- `JSONDecoder.fplAPI` converts snake_case and parses `news_added`'s fractional seconds, which `.iso8601` rejects.
- `nowCost` is tenths of a million: use `element.price`. `team` is the team id (1–20); `teamCode` is a different code, never for lookups.
- Unknown `status` codes decode to `.unknown`. `news` can be `""`: use `currentNews`. Use `isSelectable` to decide whether to show a player; status `u` alone hides nobody.

## Requests

- **Each list loads once at launch** (`RequestCountTests` checks the counts):
  - `FPLAPIClient` shares identical requests in flight for `teams`, `events`, `fixtures` and `elements` only (`sharedPaths`). A shared request isn't cancelled with its caller.
  - The "became active" refresh skips a return under 10 seconds after the last.
  - `TeamsAndFixturesStore.shared` and `GameweekStore.shared` serve every screen.
- `elements/position/{n}` loads when All players opens, never at launch. Its 404 means empty.
- `fetchElements()` numbers each request (`fetchGeneration`) and only the newest writes state; its `defer` always clears `isLoading`. Don't go back to returning early on `Task.isCancelled`: that left the spinner running forever.
- The full-screen spinner shows only with nothing loaded; refreshing keeps the list. Switching position clears the list.

## Logging

- Log at the edges, not in views: `FPLAPIClient` logs failed requests and decoding errors with their key path.
- Levels: `debug` detail, `info` notable, `notice` worth keeping (link, unlink), `error` handled failures, `fault` never expected.
- Mark only safe values `.public`: routes (`FPLAPIClient.route` hides the manager id), status codes, counts, server `detail`, `error.logSummary`. Log the error itself with no privacy option.
- Read logs: `xcrun simctl spawn booted log stream --level debug --predicate 'subsystem == "rafael.lopez.FPL"'`.
