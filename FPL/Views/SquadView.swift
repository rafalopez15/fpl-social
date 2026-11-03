//
//  SquadView.swift
//  FPL
//

import SwiftUI

/// Profile's "Your squad": the starting XI by position and the bench, as of the
/// latest deadline (FPL-36), with points (FPL-37). A stepper in the header goes
/// back through earlier gameweeks. Tapping a player opens the same stats popover
/// as the Players tab.
struct SquadSection: View {
    @EnvironmentObject private var teamStore: LinkedTeamStore
    @StateObject private var lookups = TeamsAndFixturesStore()
    /// The gameweek picked in the stepper; nil follows the latest squad.
    @State private var selected: Int?

    /// The earlier gameweek being shown, or nil for the latest squad.
    private var earlier: Int? {
        guard let selected, let range = teamStore.squadGameweeks,
              range.contains(selected), selected < range.upperBound else { return nil }
        return selected
    }

    private var state: SquadState {
        earlier.map { teamStore.earlierSquads[$0] ?? .loading } ?? teamStore.squad
    }

    private var livePoints: LivePoints? {
        earlier.map { teamStore.earlierPoints[$0] } ?? teamStore.livePoints
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR SQUAD")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let range = teamStore.squadGameweeks, range.count > 1 {
                    GameweekStepper(range: range, gameweek: Binding(
                        get: { earlier ?? range.upperBound },
                        set: { selected = $0 == range.upperBound ? nil : $0 }
                    ))
                }
            }
            // The stepper's 44pt buttons shouldn't push the card down.
            .frame(height: 20)

            switch state {
            case .loading:
                SquadPlaceholder()
            case .loaded(let picks):
                SquadCard(picks: picks, players: teamStore.players, livePoints: livePoints, lookups: lookups)
                if earlier == nil {
                    // FPL publishes picks at the deadline, so newer transfers aren't in them yet.
                    Text("Updates at each deadline, so transfers made since the last one aren't shown yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .none:
                message(earlier.map { "No squad for Gameweek \($0)." }
                        ?? "No squad yet. It shows once the season's first deadline has passed.")
            case .failed:
                HStack {
                    message("Couldn't load your squad.")
                    Spacer()
                    Button("Retry") { Task { await load() } }
                }
            }
        }
        // Again whenever the squad state changes (it loads, Retry, a new deadline),
        // so teams or fixtures that failed to load come back without leaving the tab.
        .task(id: state) { await lookups.loadIfNeeded() }
        .task(id: earlier) {
            if let earlier { await teamStore.loadSquad(gameweek: earlier) }
        }
        // A different team starts again from its latest squad.
        .onChange(of: teamStore.linked?.id) { selected = nil }
    }

    private func load() async {
        if let earlier { await teamStore.loadSquad(gameweek: earlier) } else { await teamStore.refresh() }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "‹ GW 9 ›": the arrows step a gameweek, and the label opens a menu of every
/// gameweek in `range`. VoiceOver can also swipe up or down on the label.
private struct GameweekStepper: View {
    let range: ClosedRange<Int>
    @Binding var gameweek: Int

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", label: "Previous gameweek", to: gameweek - 1)

            Menu {
                Picker("Gameweek", selection: $gameweek) {
                    ForEach(range.reversed(), id: \.self) { gameweek in
                        Text(gameweek == range.upperBound ? "Gameweek \(gameweek) (latest)" : "Gameweek \(gameweek)")
                            .tag(gameweek)
                    }
                }
            } label: {
                Text("GW \(gameweek)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .frame(minWidth: 52, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Gameweek \(gameweek)")
            .accessibilityHint("Choose a gameweek")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(to: gameweek + 1)
                case .decrement: step(to: gameweek - 1)
                @unknown default: break
                }
            }

            arrow("chevron.right", label: "Next gameweek", to: gameweek + 1)
        }
        .padding(.trailing, -12)
    }

    private func arrow(_ systemImage: String, label: String, to target: Int) -> some View {
        Button {
            step(to: target)
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(range.contains(target) ? Theme.accent : Theme.border)
        .disabled(!range.contains(target))
        .accessibilityLabel(label)
    }

    private func step(to target: Int) {
        guard range.contains(target) else { return }
        gameweek = target
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct SquadCard: View {
    let picks: ManagerPicks
    let players: [Int: Element]
    let livePoints: LivePoints?
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
                SquadPitch(picks: picks, players: players, livePoints: livePoints, lookups: lookups)
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
                             teams: lookups.teams,
                             score: livePoints?.score(for: pick, team: element.team))
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
    let score: PickScore?

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
                                  fixtures: fixtures, teams: teams, showsStats: false)

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

                if let score {
                    Text(score.text)
                        .font(.headline)
                        .monospacedDigit()
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

    /// e.g. "Haaland, Man City, captain, 16 points, subbed in, 75% chance of playing"
    private var accessibilityLabel: String {
        var parts = [element.webName]
        if let team { parts.append(team.name) }
        switch pick.badge {
        case "TC": parts.append("triple captain")
        case "C": parts.append("captain")
        case "V": parts.append("vice-captain")
        default: break
        }
        if let score { parts.append(score.accessibilityDescription) }
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
