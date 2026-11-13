---
paths:
  - "FPL/ViewModel/LinkedTeamStore.swift"
  - "FPL/ViewModel/TeamSync.swift"
  - "FPL/ViewModel/LinkTeamModel.swift"
  - "FPL/ViewModel/LeagueStandingsModel.swift"
  - "FPL/Model/Manager.swift"
  - "FPL/Model/AccountTeam.swift"
  - "FPL/Model/History.swift"
  - "FPL/Model/Picks.swift"
  - "FPL/Model/League.swift"
  - "FPL/Model/Transfer.swift"
  - "FPL/Views/ProfileView.swift"
  - "FPL/Views/LinkTeamForm.swift"
  - "FPL/Views/FollowingView.swift"
  - "FPL/Views/LeaguesView.swift"
  - "FPL/Views/SquadView.swift"
  - "FPL/Views/PitchView.swift"
  - "FPL/Views/PointsLabel.swift"
  - "FPLTests/TeamSyncTests.swift"
  - "FPLTests/LeagueTests.swift"
  - "FPLTests/ProfileRefreshTests.swift"
---

# Teams, squad and leagues

## Linked team

- Signed out, the link lives in UserDefaults (`LinkedTeamStore`, key `linkedTeam`). Signed in, `TeamSync` holds the account's `mine` and `following` teams; Profile shows one of yours through `LinkedTeamStore`.
- **Look up only teams the account list hasn't named, at most 4 at a time** (`TeamSync.maxLookups`). Keep the cap even once every team is named.
- Team changes go straight to the API with no offline queue; link or add only shows a team after its `PUT` worked. Errors show where the change was made (`TeamSync.errors`).
- A device-linked team is PUT as `mine` on sign-in without asking, unless the account has it already. A team left by signing out never joins the next account.
- `transfersSeenUntil` is per team and set only on first link, so switching back still prompts. An automatic switch waits while the transfer prompt is up.
- Until `TeamSync.hasLoaded`, an empty list isn't "none": show loading or the failure.
- Your own team can't be followed.

## Team card and transfers

- Squad value is `last_deadline_value` minus `last_deadline_bank`: FPL's value includes the bank.
- `FreeTransfers.available` works free transfers out from history: 1 after the joining gameweek, +1 per gameweek minus used, never below 0, up to 5. Wildcard and Free Hit keep what you had without adding 1. Mid-season top-ups can't be known; update it there if FPL changes the rules.
- `FPLAPIClient.transfers` drops churn rows. If the API's database is down a chip week comes back unmarked, so the prompt waits while any gameweek has over 15 new transfers (`Transfer.hasUnmarkedChurn`).

## Squad

- Points come from `/events/{gw}/live` for the picks' gameweek (`entry_history.event`) times the multiplier, never from `players`' `event_points`, which can be a gameweek old.
- "–" means yet to play: his team has a match not kicked off and he has no minutes (`LivePoints.score(for:team:)`). FPL's 0 minutes looks the same before and after a match.
- If live points fail, cards show the next opponent on its difficulty color instead.
- Kit colors from `primary_color`/`secondary_color`; goalkeepers always `Theme.goalkeeperShirt`; null colors fall back to grey. Only kits under 3:1 contrast get a hairline (`KitColors.needsHairline`).
- At accessibility text sizes the squad is a list grouped by position.
- Earlier gameweeks (`loadSquad(gameweek:)`) are kept for the session. A 404 means no squad for that gameweek, not a failure.

## Leagues

- Leagues come from the linked team's `/managers/{id}`, which `refresh()` already loads: no extra request.
- Standings show the top 50 (`LeagueStandingsModel.defaultMaxPages`); each page is an FPL call unless cached. The model still pages, for when the cap is raised.
- Once standings load, your rank comes from them (`standing(of:)`), so the two lists never disagree.
- A rank or last rank of 0 is "not ranked yet": show "–" with no arrow.
- Rows show team names only and aren't tappable until team pages exist (FPL-113).
