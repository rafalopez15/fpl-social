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

    /// Shown instead of a count: still loading, failed, or no leagues.
    private var placeholder: String {
        if leagues != nil { return Self.summary(count: 0) }
        return teamStore.managerFailed ? "Couldn't load leagues" : "Loading…"
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
                row(placeholder, chevron: false)
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

/// A league's standings: your rank, then its top teams. Teams that joined this
/// gameweek show apart, since FPL ranks them only after its next update.
struct LeagueStandingsView: View {
    let league: ManagerLeague
    /// The linked team, highlighted in the list.
    let teamID: Int
    @StateObject private var model: LeagueStandingsModel
    @State private var toast: Toast?

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
            let reloaded = await Task { await model.reload() }.value
            if !reloaded { toast = Toast(message: ProfileRefresh.failedMessage) }
        }
        .toast($toast)
    }

    /// From the team's league list, so it shows straight away, even in a league too
    /// big to reach the team. Its row in the standings, loaded later, wins when it's there.
    private var yourRank: some View {
        let row = model.standing(of: teamID)
        let rank = row?.rank ?? league.rank
        let change = row?.rankChange ?? league.rankChange
        return HStack {
            Text("Your rank")
                .font(.body.weight(.semibold))
            Spacer()
            RankLabel(rank: rank, size: league.size, change: change)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rank")
        .accessibilityValue(LeagueRank.accessibilityText(rank: rank, size: league.size, change: change))
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

/// The standings' fixed columns, scaled with the text size.
private enum StandingColumns {
    static let rank: CGFloat = 64
    static let points: CGFloat = 44

    /// From this size the columns leave too little room for a name, so rows stack.
    static func stacks(at size: DynamicTypeSize) -> Bool { size >= .xxLarge }
}

/// Column titles over the standings, lined up with `StandingRow`.
private struct StandingsHeader: View {
    @ScaledMetric(relativeTo: .body) private var rankWidth = StandingColumns.rank
    @ScaledMetric(relativeTo: .body) private var pointsWidth = StandingColumns.points
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Stacked rows label their own numbers.
        if StandingColumns.stacks(at: typeSize) {
            Text("Top teams")
        } else {
            HStack(spacing: 8) {
                Text("Rank")
                    .frame(width: rankWidth, alignment: .leading)
                Text("Team")
                Spacer()
                Text("GW")
                    .frame(width: pointsWidth, alignment: .trailing)
                Text("Total")
                    .frame(width: pointsWidth, alignment: .trailing)
            }
            .accessibilityHidden(true)
        }
    }
}

/// Rank and its movement, team name, gameweek points and total.
private struct StandingRow: View {
    let team: LeagueStanding
    let isYours: Bool

    @ScaledMetric(relativeTo: .body) private var rankWidth = StandingColumns.rank
    @ScaledMetric(relativeTo: .body) private var pointsWidth = StandingColumns.points
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if StandingColumns.stacks(at: typeSize) {
                stacked
            } else {
                columns
            }
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

    private func name(lines: Int?) -> some View {
        Text(team.entryName)
            .font(.body.weight(isYours ? .semibold : .regular))
            .lineLimit(lines)
            .minimumScaleFactor(0.8)
    }

    private var columns: some View {
        HStack(spacing: 8) {
            RankLabel(rank: team.rank, change: team.rankChange)
                .frame(width: rankWidth, alignment: .leading)
            name(lines: 2)
            Spacer(minLength: 4)
            Text(team.eventTotal.map(String.init) ?? "–")
                .foregroundStyle(.secondary)
                .frame(width: pointsWidth, alignment: .trailing)
            Text(team.total.map(String.init) ?? "–")
                .fontWeight(.semibold)
                .frame(width: pointsWidth, alignment: .trailing)
        }
    }

    /// The name gets the row's width, with the numbers under it.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                RankLabel(rank: team.rank, change: team.rankChange)
                name(lines: nil)
            }
            Text("GW \(team.eventTotal.map(String.init) ?? "–") · Total \(team.total.map(String.init) ?? "–")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
