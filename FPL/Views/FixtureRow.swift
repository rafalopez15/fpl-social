//
//  FixtureRow.swift
//  FPL
//

import SwiftUI

/// One match: home team, then the kickoff time or score, then the away team.
struct FixtureRow: View {
    let fixture: Fixture
    let teams: [Int: Team]

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
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                name(home, alignment: .trailing)
                ClubDot(team: home)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            middle
                .frame(minWidth: 70)

            HStack(spacing: 8) {
                ClubDot(team: away)
                name(away, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.description(of: fixture, home: home?.name, away: away?.name))
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
    nonisolated static func description(of fixture: Fixture, home: String?, away: String?,
                                        timeZone: TimeZone = .current) -> String {
        let home = home ?? "Home team", away = away ?? "Away team"
        let scoreline = "\(home) \(fixture.teamHScore ?? 0), \(away) \(fixture.teamAScore ?? 0)"
        switch fixture.matchState {
        case .notStarted:
            var style = Date.FormatStyle(date: .omitted, time: .shortened)
            style.timeZone = timeZone
            return "\(home) v \(away), kicks off \(fixture.kickoffTime?.formatted(style) ?? "later")"
        case .live(let minute):
            return "\(scoreline), live, \(minute) \(minute == 1 ? "minute" : "minutes")"
        case .finished:
            return "\(scoreline), full time"
        case .postponed:
            return "\(home) v \(away), postponed"
        }
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
