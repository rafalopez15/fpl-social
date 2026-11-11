//
//  LeaguesView.swift
//  FPL
//

import SwiftUI

/// The Leagues part of Profile's account card: how many leagues the linked team is
/// in, opening the Leagues page. They come with the team's details, so they cost no request.
struct LeaguesCard: View {
    @EnvironmentObject private var teamStore: LinkedTeamStore

    /// "No leagues", "1 league", "24 leagues".
    nonisolated static func summary(count: Int) -> String {
        switch count {
        case 0: "No leagues"
        case 1: "1 league"
        default: "\(count.formatted()) leagues"
        }
    }

    /// The linked team's leagues; nil until its details load, or from an API without them.
    private var leagues: [ManagerLeague]? {
        guard let manager = teamStore.manager, manager.id == teamStore.linked?.id else { return nil }
        return manager.leagues
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LEAGUES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if let leagues, !leagues.isEmpty, let teamID = teamStore.linked?.id {
                NavigationLink {
                    LeaguesView(leagues: leagues, teamID: teamID)
                } label: {
                    row(Self.summary(count: leagues.count), chevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Leagues, \(Self.summary(count: leagues.count))")
            } else {
                row(leagues == nil ? "Loading…" : Self.summary(count: 0), chevron: false)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ text: String, chevron: Bool) -> some View {
        HStack {
            Text(text)
                .font(.body.weight(.semibold))
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// The linked team's leagues: the ones people made first, then FPL's own, each
/// in the API's order (smallest first). Each opens its standings.
struct LeaguesView: View {
    let leagues: [ManagerLeague]
    let teamID: Int

    private var invitational: [ManagerLeague] { leagues.filter { $0.kind == .invitational } }
    private var general: [ManagerLeague] { leagues.filter { $0.kind != .invitational } }

    var body: some View {
        List {
            if !invitational.isEmpty {
                Section("Leagues") {
                    ForEach(invitational) { row($0) }
                }
            }
            if !general.isEmpty {
                Section("General leagues") {
                    ForEach(general) { row($0) }
                }
            }
        }
        .themedScreen()
        .navigationTitle("Leagues")
        .navigationBarTitleDisplayMode(.inline)
        // Profile hides its bar; this page needs one for Back.
        .toolbar(.visible, for: .navigationBar)
    }

    private func row(_ league: ManagerLeague) -> some View {
        NavigationLink {
            LeagueStandingsView(league: league, teamID: teamID)
        } label: {
            HStack(spacing: 12) {
                Text(league.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                RankLabel(rank: league.rank, change: league.rankChange)
            }
            .frame(minHeight: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(league.name)
        .accessibilityValue(LeagueRank.accessibilityText(rank: league.rank, size: nil, change: league.rankChange))
        .accessibilityAddTraits(.isButton)
        .themedRow()
    }
}

/// "▲ 3 of 23": rank, with a green up or red down arrow for the change since the
/// gameweek before. "–" before the team is ranked.
struct RankLabel: View {
    let rank: Int?
    var size: Int?
    let change: Int?

    var body: some View {
        HStack(spacing: 4) {
            if let change, change != 0 {
                Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(change > 0 ? Theme.accent : Theme.danger)
            }
            Text(LeagueRank.text(rank: rank, size: size) ?? "–")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}

/// A league's standings, 50 teams a page, loading more as you scroll. Teams that
/// joined this gameweek show apart, since FPL ranks them only after its next update.
struct LeagueStandingsView: View {
    let league: ManagerLeague
    /// The linked team, highlighted in the list.
    let teamID: Int
    @StateObject private var model: LeagueStandingsModel

    init(league: ManagerLeague, teamID: Int) {
        self.league = league
        self.teamID = teamID
        _model = StateObject(wrappedValue: LeagueStandingsModel(leagueID: league.id))
    }

    var body: some View {
        List {
            Section {
                yourRank
            } footer: {
                if let updated = model.lastUpdated {
                    Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                }
            }

            switch model.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .themedRow()
            case .failed(let notFound):
                failed(notFound: notFound)
            case .loaded:
                standings
                newEntries
            }
        }
        .themedScreen()
        .navigationTitle(model.name ?? league.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await model.loadIfNeeded() }
        .refreshable {
            // Its own task: SwiftUI cancels the action's when the list redraws mid-load.
            await Task { await model.reload() }.value
        }
    }

    /// From the team's league list, so it shows straight away, even in a league
    /// too big to scroll to the team.
    private var yourRank: some View {
        HStack {
            Text("Your rank")
                .font(.body.weight(.semibold))
            Spacer()
            RankLabel(rank: league.rank, size: league.size, change: league.rankChange)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rank")
        .accessibilityValue(LeagueRank.accessibilityText(rank: league.rank, size: league.size, change: league.rankChange))
        .themedRow()
    }

    @ViewBuilder
    private var standings: some View {
        if !model.standings.isEmpty {
            Section {
                ForEach(model.standings) { team in
                    StandingRow(team: team, isYours: team.entry == teamID)
                        .listRowBackground(team.entry == teamID ? Theme.yourRow : Theme.surface)
                        .listRowSeparatorTint(Theme.border)
                        .onAppear {
                            if team.id == model.standings.last?.id { Task { await model.loadMore() } }
                        }
                }
                if model.moreFailed {
                    HStack {
                        Text("Couldn't load more teams")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") { Task { await model.retryMore() } }
                    }
                    .frame(minHeight: 44)
                    .themedRow()
                } else if model.hasNext, !model.isCapped {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .themedRow()
                }
            } header: {
                StandingsHeader()
            } footer: {
                if model.isCapped {
                    Text(LeagueRank.capNote(shown: model.shownLimit, size: league.size))
                }
            }
        }
    }

    @ViewBuilder
    private var newEntries: some View {
        if !model.newEntries.isEmpty {
            Section {
                ForEach(model.newEntries) { team in
                    Text(team.entryName)
                        .font(.body.weight(team.entry == teamID ? .semibold : .regular))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(minHeight: 44)
                        .listRowBackground(team.entry == teamID ? Theme.yourRow : Theme.surface)
                        .listRowSeparatorTint(Theme.border)
                }
            } header: {
                Text("Joined this gameweek")
            } footer: {
                Text(model.newEntriesHasNext
                     ? "Ranked after FPL's next update. Only the first 50 are shown."
                     : "Ranked after FPL's next update.")
            }
        } else if model.standings.isEmpty {
            Text("No teams in this league yet")
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .themedRow()
        }
    }

    private func failed(notFound: Bool) -> some View {
        HStack {
            Text(notFound ? "FPL couldn't find this league" : "Couldn't load the standings")
                .foregroundStyle(.secondary)
            Spacer()
            if !notFound {
                Button("Retry") { Task { await model.loadIfNeeded() } }
            }
        }
        .frame(minHeight: 44)
        .themedRow()
    }
}

/// Column titles over the standings, lined up with `StandingRow`.
private struct StandingsHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Rank")
                .frame(width: StandingRow.rankWidth, alignment: .leading)
            Text("Team")
            Spacer()
            Text("GW")
                .frame(width: StandingRow.pointsWidth, alignment: .trailing)
            Text("Total")
                .frame(width: StandingRow.pointsWidth, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }
}

/// Rank and its movement, team name, gameweek points and total.
private struct StandingRow: View {
    let team: LeagueStanding
    let isYours: Bool

    static let rankWidth: CGFloat = 64
    static let pointsWidth: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            RankLabel(rank: team.rank, change: team.rankChange)
                .frame(width: Self.rankWidth, alignment: .leading)
            Text(team.entryName)
                .font(.body.weight(isYours ? .semibold : .regular))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(team.eventTotal.map(String.init) ?? "–")
                .foregroundStyle(.secondary)
                .frame(width: Self.pointsWidth, alignment: .trailing)
            Text(team.total.map(String.init) ?? "–")
                .fontWeight(.semibold)
                .frame(width: Self.pointsWidth, alignment: .trailing)
        }
        .monospacedDigit()
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isYours ? "\(team.entryName), your team" : team.entryName)
        .accessibilityValue([
            LeagueRank.accessibilityText(rank: team.rank, size: nil, change: team.rankChange),
            team.eventTotal.map { "\($0) points this gameweek" },
            team.total.map { "\($0) in total" },
        ].compactMap { $0 }.joined(separator: ", "))
    }
}
