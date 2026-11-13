---
paths:
  - "FPL/Views/GameweekView.swift"
  - "FPL/ViewModel/GameweekFixturesModel.swift"
  - "FPL/Views/FixtureRow.swift"
  - "FPL/Model/Fixture.swift"
  - "FPL/Model/DeadlineCountdown.swift"
  - "FPLTests/GameweekFixturesTests.swift"
  - "FPLTests/GameweekLiveTests.swift"
  - "FPLTests/GameweekExtrasTests.swift"
---

# Gameweek tab

- **Full time is `finishedProvisional` (or `finished`), never `finished` alone**: FPL sets `finished` a day or more after the final whistle. Only `/events/{gw}/fixtures` sends `finishedProvisional`, so `Fixture.matchState` is wrong for the stored `/fixtures` list.
- **A 404 is a failure; only `200 []` is the empty state** ("No matches this gameweek."). A 404 means the API doesn't have the gameweek, or a backend preview older than the route.
- A cancelled load isn't a failure: the gameweek stays as it was and `open` runs again next time.
- **Nothing loads until the tab is first shown.** The load is keyed on `hasBeenShown`, not `isSelected`, so leaving the tab mid-load doesn't cancel it.
- **Only the newest selection's answer is shown** (`selection` counter). Stepping shows a gameweek loaded earlier this session at once, then the latest.
- **The opening gameweek is decided once** (`open`, `Fixture.gameweekToOpen`): current, or next once every scheduled match of current is over, judged from current's own matches since FPL's gameweek `finished` lags. Don't re-decide it on reload or when returning to the tab.
- Postponed matches (no kickoff time) go in a "Postponed" section at the bottom.
- **The deadline countdown is always the next deadline still to come** (`DeadlineCountdown.next(in:now:)`), whichever gameweek is shown, so it names its gameweek. It replaced the header's deadline line: don't show both. It's driven by `TimelineView(.everyMinute)`, not a timer.
- **Your players per match count starters only** (`ManagerPicks.players(in:from:)`), from the squad and players Profile already loaded: no request. A spacer as wide as the count keeps the score centered.
- **A team's next fixtures count matches, not gameweeks** (`FixtureSchedule.next(_:for:)`, from `TeamsAndFixturesStore.schedule`): a double takes two, a blank is skipped. No request.
- **It refreshes itself every 60 seconds** (the endpoint's cache time) only while the tab is selected, the app is active and `refreshesItself` (a match is live or the copy is stale). A failed load with fixtures on screen keeps them and shows "Couldn't update".
- **A saved copy** (`X-Data-Stale-As-Of`, read into `staleAsOf` per gameweek) shows "FPL is updating · showing scores as of …", and a match in play shows a grey score with no LIVE tag or minute (`FixtureRow.isStale`). A header that doesn't parse counts as fresh.
