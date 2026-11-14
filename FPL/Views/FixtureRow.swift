//
//  FixtureRow.swift
//  FPL
//

import SwiftUI

/// One match: home team, then the kickoff time or score, then the away team.
struct FixtureRow: View {
    let fixture: Fixture
    let teams: [Int: Team]
    /// A saved copy from while FPL is down: a match in play isn't shown as live.
    var isStale = false
    /// Your squad's players in this match. Nil without a squad, which leaves no room for a count.
    var yourPlayers: [ManagerPicks.SquadPlayer]?
    /// Called with the team whose name was tapped. Nil leaves names as plain text.
    var onTeam: ((Team) -> Void)?
    @State private var showsYourPlayers = false
    @ScaledMetric(relativeTo: .caption) private var countWidth: CGFloat = 34

    static var placeholder: some View {
        FixtureRow(fixture: Fixture(id: 0, event: nil, teamH: 0, teamA: 0, teamHDifficulty: 3, teamADifficulty: 3,
                                    kickoffTime: .now, started: false, finished: false, teamHScore: nil, teamAScore: nil),
                   teams: [:])
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }

    private var home: Team? { teams[fixture.teamH] }
    private var away: Team? { teams[fixture.teamA] }

    private var score: String {
        "\(fixture.teamHScore ?? 0) - \(fixture.teamAScore ?? 0)"
    }

    var body: some View {
        HStack(spacing: 4) {
            // As wide as the count, so the score stays in the middle of the row.
            if yourPlayers != nil { Color.clear.frame(width: countWidth, height: 1) }
            match
            if let yourPlayers { count(yourPlayers) }
        }
    }

    /// How many of your players are in the match; tapping it lists them.
    @ViewBuilder
    private func count(_ players: [ManagerPicks.SquadPlayer]) -> some View {
        if players.isEmpty {
            Color.clear.frame(width: countWidth, height: 1)
        } else {
            Button {
                showsYourPlayers = true
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                    Text("\(players.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
                .foregroundStyle(Theme.accent)
                .frame(width: countWidth)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Self.countDescription(players.count))
            .accessibilityHint("Lists them")
            // Below the count, so it doesn't cover the match it lists.
            .popover(isPresented: $showsYourPlayers, arrowEdge: .top) {
                YourPlayersList(players: players, teams: teams)
                    .presentationBackground(Theme.raised)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    /// "1 of your players", "2 of your players".
    nonisolated static func countDescription(_ count: Int) -> String {
        "\(count) of your players"
    }

    private var match: some View {
        HStack(spacing: 10) {
            side(home) {
                name(home, alignment: .trailing)
                ClubDot(team: home)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            middle
                .frame(minWidth: 70)

            side(away) {
                ClubDot(team: away)
                name(away, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.description(of: fixture, home: home?.name, away: away?.name, isStale: isStale))
        .accessibilityActions {
            if let onTeam {
                ForEach([home, away].compactMap { $0 }) { team in
                    Button("\(team.name)'s next fixtures") { onTeam(team) }
                }
            }
        }
    }

    /// A team's name and dot, which open its next fixtures when there's somewhere to open them.
    @ViewBuilder
    private func side(_ team: Team?, @ViewBuilder content: () -> some View) -> some View {
        let label = HStack(spacing: 8, content: content)
        if let team, let onTeam {
            Button { onTeam(team) } label: {
                label
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    /// The team's name, or its short name where the name doesn't fit.
    private func name(_ team: Team?, alignment: Alignment) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(team?.name ?? "–")
            Text(team?.shortName ?? "–")
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    @ViewBuilder
    private var middle: some View {
        switch fixture.matchState {
        case .notStarted:
            chip {
                Text(fixture.kickoffTime?.formatted(date: .omitted, time: .shortened) ?? "–")
                    .font(.footnote.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .live where isStale:
            chip {
                Text(score)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .live(let minute):
            VStack(spacing: 3) {
                chip(border: Theme.accent) {
                    Text(score)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                }
                HStack(spacing: 4) {
                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                    Text("\(minute)'")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 6)
        case .finished:
            chip {
                Text(score)
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
        case .postponed:
            Text("Postponed")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// The time or score on a darker chip, so the middle column reads as one line down the list.
    private func chip(border: Color = .clear, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(minWidth: 58, minHeight: 28)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(border) }
    }

    /// What VoiceOver reads: "Arsenal 2, Chelsea 1, live, 67 minutes".
    nonisolated static func description(of fixture: Fixture, home: String?, away: String?, isStale: Bool = false,
                                        timeZone: TimeZone = .current) -> String {
        let home = home ?? "Home team", away = away ?? "Away team"
        let scoreline = "\(home) \(fixture.teamHScore ?? 0), \(away) \(fixture.teamAScore ?? 0)"
        switch fixture.matchState {
        case .notStarted:
            var style = Date.FormatStyle(date: .omitted, time: .shortened)
            style.timeZone = timeZone
            return "\(home) v \(away), kicks off \(fixture.kickoffTime?.formatted(style) ?? "later")"
        case .live where isStale:
            return "\(scoreline), last known score"
        case .live(let minute):
            return "\(scoreline), live, \(minute) \(minute == 1 ? "minute" : "minutes")"
        case .finished:
            return "\(scoreline), full time"
        case .postponed:
            return "\(home) v \(away), postponed"
        }
    }
}

/// Your starting players in one match: name, club and position, with the captain's badge.
private struct YourPlayersList: View {
    let players: [ManagerPicks.SquadPlayer]
    let teams: [Int: Team]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your players")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityAddTraits(.isHeader)
            ForEach(players) { player in
                HStack(spacing: 6) {
                    Text(player.element.webName)
                        .font(.subheadline.weight(.semibold))
                    if let badge = player.pick.badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 4)
                            .background(Theme.accent, in: Capsule())
                    }
                    Spacer(minLength: 12)
                    Text(Self.detail(of: player, teams: teams))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.description(of: player, teams: teams))
            }
        }
        .padding(16)
        .frame(minWidth: 220)
    }

    /// "ARS · MID"
    nonisolated static func detail(of player: ManagerPicks.SquadPlayer, teams: [Int: Team]) -> String {
        [teams[player.element.team]?.shortName, player.element.position?.shortTitle]
            .compactMap { $0 }.joined(separator: " · ")
    }

    nonisolated static func description(of player: ManagerPicks.SquadPlayer, teams: [Int: Team]) -> String {
        let role: String? = switch player.pick.badge {
        case "C", "TC": "captain"
        case "V": "vice captain"
        default: nil
        }
        return [player.element.webName, role, teams[player.element.team]?.name, player.element.position?.singularTitle]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// A team's next matches: gameweek and date, opponent, and FPL's difficulty.
struct TeamFixturesSheet: View {
    let team: Team
    let teams: [Int: Team]
    /// Nil when the schedule couldn't load.
    let fixtures: [NextFixture]?
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ClubDot(team: team)
                Text(team.name)
                    .font(.title3.weight(.bold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let fixtures, fixtures.isEmpty {
                Text("No upcoming fixtures.")
                    .foregroundStyle(.secondary)
            } else if let fixtures {
                Text(fixtures.count == 1 ? "NEXT FIXTURE" : "NEXT \(fixtures.count) FIXTURES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    ForEach(fixtures) { fixture in
                        row(fixture)
                    }
                }
            } else {
                HStack {
                    Text("Couldn't load fixtures")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { Task { await retry() } }
                }
                .frame(minHeight: 44)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ next: NextFixture) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(teams[next.fixture.opponent]?.name ?? "–") (\(next.fixture.isHome ? "H" : "A"))")
                    .font(.subheadline.weight(.semibold))
                Text(Self.when(next))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            DifficultyChip(difficulty: next.fixture.difficulty)
                .frame(width: 44)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.description(of: next, opponent: teams[next.fixture.opponent]?.name))
    }

    /// "GW11 · Sat, Nov 21", or the gameweek alone without a kickoff time.
    nonisolated static func when(_ next: NextFixture, timeZone: TimeZone = .current) -> String {
        guard let kickoff = next.kickoffTime else { return "GW\(next.gameweek)" }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = timeZone
        return "GW\(next.gameweek) · \(kickoff.formatted(style))"
    }

    /// "Gameweek 11: Chelsea, home, difficulty 3"
    nonisolated static func description(of next: NextFixture, opponent: String?) -> String {
        let side = next.fixture.isHome ? "home" : "away"
        return "Gameweek \(next.gameweek): \(opponent ?? "Unknown team"), \(side), difficulty \(next.fixture.difficulty)"
    }
}

/// The club's home color as a dot; grey for a club with no colors.
private struct ClubDot: View {
    let team: Team?

    var body: some View {
        Circle()
            .fill(Color(hex: KitColors(primary: team?.primaryColor, secondary: team?.secondaryColor).primary))
            // Dark kits would vanish into the navy row without it.
            .overlay { Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1) }
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }
}

#Preview("Row states") {
    let teams = [1: Team(id: 1, name: "Arsenal", shortName: "ARS", primaryColor: "#EF0107"),
                 2: Team(id: 2, name: "Newcastle", shortName: "NEW", primaryColor: "#241F20"),
                 3: Team(id: 3, name: "Nott'm Forest", shortName: "NFO")]
    func fixture(_ id: Int, home: Int, away: Int, kickoff: Date? = .now, started: Bool = false,
                 score: (Int, Int)? = nil, minutes: Int? = 0, fullTime: Bool = false) -> Fixture {
        Fixture(id: id, event: 10, teamH: home, teamA: away, teamHDifficulty: 3, teamADifficulty: 3,
                kickoffTime: kickoff, started: started, finished: false,
                teamHScore: score?.0, teamAScore: score?.1, minutes: minutes, finishedProvisional: fullTime)
    }
    return List {
        Section("Upcoming, live, full time") {
            FixtureRow(fixture: fixture(1, home: 1, away: 2), teams: teams).themedRow()
            FixtureRow(fixture: fixture(2, home: 2, away: 3, started: true, score: (1, 0), minutes: 67),
                       teams: teams).themedRow()
            FixtureRow(fixture: fixture(3, home: 3, away: 1, started: true, score: (2, 2), minutes: 90, fullTime: true),
                       teams: teams).themedRow()
        }
        Section("Postponed") {
            FixtureRow(fixture: fixture(4, home: 1, away: 3, kickoff: nil), teams: teams).themedRow()
        }
        Section("In play in a saved copy") {
            FixtureRow(fixture: fixture(5, home: 2, away: 3, started: true, score: (1, 0), minutes: 67),
                       teams: teams, isStale: true).themedRow()
        }
        Section("Empty gameweek") {
            Text("No matches this gameweek.")
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .themedRow()
        }
        Section("Loading") {
            FixtureRow.placeholder.themedRow()
        }
    }
    .listStyle(.insetGrouped)
    .themedScreen()
}
