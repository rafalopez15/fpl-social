//
//  SquadView.swift
//  FPL
//

import SwiftUI

/// Profile's "Your squad": the starting XI by position and the bench, as of the
/// latest deadline (FPL-36). Tapping a player opens the same stats popover as
/// the Players tab.
struct SquadSection: View {
    let state: SquadState
    let players: [Int: Element]
    let onRetry: () -> Void

    @StateObject private var lookups = TeamsAndFixturesStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR SQUAD")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            switch state {
            case .loading:
                SquadPlaceholder()
            case .loaded(let picks):
                SquadCard(picks: picks, players: players, lookups: lookups)
                // FPL publishes picks at the deadline, so newer transfers aren't in them yet.
                Text("Updates at each deadline, so transfers made since the last one aren't shown yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .none:
                message("No squad yet. It shows once the season's first deadline has passed.")
            case .failed:
                HStack {
                    message("Couldn't load your squad.")
                    Spacer()
                    Button("Retry", action: onRetry)
                }
            }
        }
        // Again whenever the squad state changes (it loads, Retry, a new deadline),
        // so teams or fixtures that failed to load come back without leaving the tab.
        .task(id: state) { await lookups.loadIfNeeded() }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SquadCard: View {
    let picks: ManagerPicks
    let players: [Int: Element]
    @ObservedObject var lookups: TeamsAndFixturesStore
    /// At accessibility text sizes the pitch's cards can't fit, so the squad shows as a list.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if typeSize.isAccessibilitySize {
                ForEach(picks.startingLines(players: players), id: \.position) { line in
                    Divider()
                    group(line.position.title.uppercased(), line.picks)
                }

                if !picks.bench.isEmpty {
                    Divider()
                    group("BENCH", picks.bench)
                }
            } else {
                SquadPitch(picks: picks, players: players, lookups: lookups)
                    // Into the card's padding: a 5-man midfield needs the width.
                    .padding(.horizontal, -8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// "Gameweek 9 · 45 pts" over "15 pts on the bench", with the chip on the right.
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let bench = picks.entryHistory?.pointsOnBench {
                    Text("\(bench) pts on the bench")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer()

            if let chip = picks.chipTitle {
                Text(chip)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.6)))
                    .accessibilityLabel("\(chip) played")
            }
        }
    }

    private var title: String {
        var parts: [String] = []
        if let event = picks.entryHistory?.event { parts.append("Gameweek \(event)") }
        if let points = picks.entryHistory?.points { parts.append("\(points) pts") }
        return parts.isEmpty ? "Your squad" : parts.joined(separator: " · ")
    }

    private func group(_ title: String, _ picks: [ManagerPicks.Pick]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(picks) { pick in
                if let element = players[pick.element] {
                    SquadRow(pick: pick, element: element,
                             team: lookups.teams[element.team],
                             subbedIn: self.picks.subbedIn.contains(pick.element),
                             subbedOut: self.picks.subbedOut.contains(pick.element),
                             fixtures: lookups.schedule?.upcoming(for: element.team) ?? [],
                             teams: lookups.teams)
                }
            }
        }
    }

    private struct Divider: View {
        var body: some View {
            Rectangle().fill(Theme.border).frame(height: 1).accessibilityHidden(true)
        }
    }
}

/// One player: info icon, flag, name and team, then the captain badge and any
/// automatic sub. The whole row opens the stats popover.
private struct SquadRow: View {
    let pick: ManagerPicks.Pick
    let element: Element
    let team: Team?
    let subbedIn: Bool
    let subbedOut: Bool
    let fixtures: [GameweekFixtures]
    let teams: [Int: Team]

    @State private var showingStats = false

    var body: some View {
        Button {
            showingStats = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                    // Anchored on the icon, as on the Players tab, so iOS can place
                    // the popover beside the row wherever it fits on screen.
                    .statsPopover(isPresented: $showingStats, element: element, team: team,
                                  fixtures: fixtures, teams: teams)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let flag = element.availabilityFlag {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.color(for: flag))
                    }
                    Text(element.webName)
                        .font(.headline)
                        .foregroundStyle(element.availabilityFlag.map(Theme.color(for:)) ?? Theme.text)
                    if let team {
                        Text(team.shortName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let badge = pick.badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(pick.isCaptain == true ? Theme.onAccent : Theme.text)
                        .frame(minWidth: 22, minHeight: 22)
                        .padding(.horizontal, badge.count > 1 ? 3 : 0)
                        .background(pick.isCaptain == true ? Theme.accent : Theme.border, in: Capsule())
                }

                Spacer(minLength: 8)

                if subbedIn {
                    subLabel("Subbed in", systemImage: "arrow.up.circle.fill", color: Theme.accent)
                } else if subbedOut {
                    subLabel("Subbed out", systemImage: "arrow.down.circle.fill", color: Theme.danger)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Shows stats and news")
        .accessibilityAddTraits(.isButton)
    }

    private func subLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }

    /// e.g. "Haaland, Man City, captain, subbed in, 75% chance of playing"
    private var accessibilityLabel: String {
        var parts = [element.webName]
        if let team { parts.append(team.name) }
        switch pick.badge {
        case "TC": parts.append("triple captain")
        case "C": parts.append("captain")
        case "V": parts.append("vice-captain")
        default: break
        }
        if subbedIn { parts.append("subbed in") }
        if subbedOut { parts.append("subbed out") }
        if element.availabilityFlag != nil { parts.append(element.availabilityDescription) }
        return parts.joined(separator: ", ")
    }
}

/// Grey rows in the card's shape while the squad loads.
private struct SquadPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gameweek 10 · 50 pts").font(.headline)
            ForEach(0..<6, id: \.self) { _ in
                Text("Player name TEAM").font(.headline)
                    .frame(minHeight: 44)
            }
        }
        .redacted(reason: .placeholder)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your squad")
    }
}
