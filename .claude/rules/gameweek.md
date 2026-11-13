---
paths:
  - "FPL/Views/GameweekView.swift"
  - "FPL/ViewModel/GameweekFixturesModel.swift"
  - "FPL/Model/Fixture.swift"
  - "FPLTests/GameweekFixturesTests.swift"
---

# Gameweek tab

- **Full time is `finishedProvisional` (or `finished`), never `finished` alone**: FPL sets `finished` a day or more after the final whistle. Only `/events/{gw}/fixtures` sends `finishedProvisional`, so `Fixture.matchState` is wrong for the stored `/fixtures` list.
- **A 404 is a failure; only `200 []` is the empty state** ("No matches this gameweek."). A 404 means the API doesn't have the gameweek, or a backend preview older than the route.
- A cancelled load isn't a failure: the gameweek stays as it was and `open` runs again next time.
- **Nothing loads until the tab is first shown.** The load is keyed on `hasBeenShown`, not `isSelected`, so leaving the tab mid-load doesn't cancel it.
- **Only the newest selection's answer is shown** (`selection` counter). Stepping shows a gameweek loaded earlier this session at once, then the latest.
- **The opening gameweek is decided once** (`open`, `Fixture.gameweekToOpen`): current, or next once every scheduled match of current is over, judged from current's own matches since FPL's gameweek `finished` lags. Don't re-decide it on reload or when returning to the tab.
- Postponed matches (no kickoff time) go in a "Postponed" section at the bottom.
