//
//  ElementStatsView.swift
//  FPL
//

import SwiftUI

/// Season and advanced stats for one player, shown in a popover from the list.
struct ElementStatsView: View {
    let element: Element
    let team: Team?
    /// The player's team's next gameweeks. Empty hides the section.
    var fixtures: [GameweekFixtures] = []
    /// All teams by id, for opponent short names.
    var teams: [Int: Team] = [:]

    var body: some View {
        // 12pt between blocks, with a hairline between sections so each reads as its own group.
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(element.fullName)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let selectedBy = element.selectedByPercent {
                    Text(String(format: "Selected by %.1f%%", selectedBy))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if element.availabilityFlag != nil || element.currentNews != nil {
                NewsCallout(element: element)
            }

            if !fixtures.isEmpty {
                SectionDivider()
                FixturesSection(gameweeks: fixtures, teams: teams)
            }

            SectionDivider()

            StatSection(title: "Season", stats: [
                ("Minutes", int(element.minutes)),
                ("Starts", int(element.starts)),
                ("Goals", int(element.goalsScored)),
                ("Assists", int(element.assists)),
                ("Clean sheets", int(element.cleanSheets)),
                ("Goals conceded", int(element.goalsConceded)),
                ("Saves", int(element.saves)),
                ("Bonus", int(element.bonus)),
                ("Yellow cards", int(element.yellowCards)),
                ("Red cards", int(element.redCards)),
            ])

            SectionDivider()

            StatSection(title: "Advanced", stats: [
                ("xG", decimal(element.expectedGoals, places: 2)),
                ("xA", decimal(element.expectedAssists, places: 2)),
                ("xGI", decimal(element.expectedGoalInvolvements, places: 2)),
                ("xGC", decimal(element.expectedGoalsConceded, places: 2)),
                ("ICT index", decimal(element.ictIndex, places: 1)),
            ])
        }
        .padding()
        .frame(width: 300)
    }

    /// e.g. "Forward · Man City"
    private var subtitle: String {
        [element.position?.singularTitle, team?.name]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func int(_ value: Int?) -> String {
        value.map(String.init) ?? "–"
    }

    private func decimal(_ value: Double?, places: Int) -> String {
        value.map { String(format: "%.\(places)f", $0) } ?? "–"
    }
}

/// Injury or availability news in the flag's color (yellow doubtful, red out),
/// or grey when the player isn't flagged.
private struct NewsCallout: View {
    let element: Element

    private var flagColor: Color? { element.availabilityFlag.map(Theme.color(for:)) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: flagColor != nil ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(flagColor ?? Theme.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(element.currentNews ?? element.availabilityDescription)
                    .foregroundStyle(flagColor ?? Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let added = element.newsAdded {
                    Text("Updated \(added, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The next gameweeks side by side: each column lists the team's fixtures in
/// that gameweek (opponent, home or away, difficulty chip), or "–" for a blank.
private struct FixturesSection: View {
    let gameweeks: [GameweekFixtures]
    let teams: [Int: Team]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FIXTURES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                ForEach(gameweeks) { gameweek in
                    column(gameweek)
                }
            }
        }
    }

    private func column(_ gameweek: GameweekFixtures) -> some View {
        VStack(spacing: 6) {
            Text("GW\(gameweek.gameweek)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if gameweek.fixtures.isEmpty {
                Text("–")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(gameweek.fixtures) { fixture in
                    VStack(spacing: 4) {
                        Text("\(opponentName(fixture)) (\(fixture.isHome ? "H" : "A"))")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        DifficultyChip(difficulty: fixture.difficulty)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(gameweek))
    }

    private func opponentName(_ fixture: TeamFixture) -> String {
        teams[fixture.opponent]?.shortName ?? "–"
    }

    /// e.g. "Gameweek 10: Hull, home, difficulty 2"
    private func accessibilityLabel(_ gameweek: GameweekFixtures) -> String {
        let fixtures = gameweek.fixtures.map { fixture in
            let name = teams[fixture.opponent]?.name ?? "Unknown team"
            return "\(name), \(fixture.isHome ? "home" : "away"), difficulty \(fixture.difficulty)"
        }
        let detail = fixtures.isEmpty ? "No fixture" : fixtures.joined(separator: "; ")
        return "Gameweek \(gameweek.gameweek): \(detail)"
    }
}

/// FPL's 1–5 fixture difficulty as a colored chip.
private struct DifficultyChip: View {
    let difficulty: Int

    var body: some View {
        let colors = Theme.difficultyColors(difficulty)
        Text("\(difficulty)")
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(colors.foreground)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(colors.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// A hairline between popover sections.
private struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A titled two-column grid of label/value pairs.
private struct StatSection: View {
    let title: String
    let stats: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(Array(stride(from: 0, to: stats.count, by: 2)), id: \.self) { index in
                    GridRow {
                        cell(stats[index])
                        // Wider gap between the two label/value pairs than within a pair.
                        Color.clear
                            .frame(width: 8, height: 1)
                            .gridCellUnsizedAxes(.vertical)
                        if index + 1 < stats.count {
                            cell(stats[index + 1])
                        }
                    }
                }
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private func cell(_ stat: (label: String, value: String)) -> some View {
        Text(stat.label)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            // Fill the width so every section's columns line up.
            .frame(maxWidth: .infinity, alignment: .leading)
        Text(stat.value)
            .monospacedDigit()
            .fontWeight(.semibold)
            .gridColumnAlignment(.trailing)
    }
}
