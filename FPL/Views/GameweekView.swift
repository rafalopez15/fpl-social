//
//  GameweekView.swift
//  FPL
//

import SwiftUI

/// The Gameweek tab: one gameweek's matches by day, with kickoff times, live scores
/// and final scores. A stepper in the header moves between gameweeks.
struct GameweekView: View {
    /// Tabs stay alive when hidden, so loading waits until this one is first shown.
    let isSelected: Bool
    @State private var hasBeenShown = false
    @EnvironmentObject private var gameweeks: GameweekStore
    @ObservedObject private var lookups = TeamsAndFixturesStore.shared
    @StateObject private var model = GameweekFixturesModel()
    @State private var toast: Toast?
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            Group {
                if let gameweek = model.gameweek {
                    list(gameweek)
                } else if gameweeks.didFail {
                    ContentUnavailableView {
                        Label("Couldn't load gameweeks", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Retry") { Task { await gameweeks.loadIfNeeded() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView()
                }
            }
            .themedScreen()
            .toast($toast)
            // Like Notes and Profile: the tab bar says where you are, so no title bar.
            .navigationTitle("Gameweek")
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: isSelected, initial: true) {
            if isSelected { hasBeenShown = true }
        }
        // Keyed on having been shown, so leaving the tab doesn't cancel the first load.
        .task(id: StartKey(hasBeenShown: hasBeenShown, current: gameweeks.current)) {
            guard hasBeenShown, let current = gameweeks.current else { return }
            async let teams: Void = lookups.loadIfNeeded()
            await model.open(current: current, next: gameweeks.events.first(where: \.isNext)?.id)
            await teams
        }
    }

    private struct StartKey: Equatable {
        let hasBeenShown: Bool
        let current: Int?
    }

    private func list(_ gameweek: Int) -> some View {
        List {
            Section {
                // With the navigation bar hidden, iOS doesn't draw the refresh spinner.
                if isRefreshing {
                    ProgressView()
                        .tint(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .accessibilityLabel("Refreshing")
                }
                header(gameweek)
                    .themedRow()
            }

            matches
        }
        .listSectionSpacing(12)
        // The grouped style's default top inset leaves a large empty band.
        .contentMargins(.top, 8, for: .scrollContent)
        .listStyle(.insetGrouped)
        .refreshable {
            isRefreshing = true
            // Its own task: SwiftUI cancels the action's when the list redraws mid-load.
            let reloaded = await Task { await model.reload() }.value
            if !reloaded { toast = Toast(ProfileRefresh.failedMessage, style: .warning) }
            isRefreshing = false
        }
    }

    /// The matches by day, or the gameweek's loading, failed or empty state.
    @ViewBuilder
    private var matches: some View {
        let (days, postponed) = FixtureDay.days(for: model.fixtures)
        switch model.state {
        case .loading:
            Section {
                ForEach(0..<5, id: \.self) { _ in
                    FixtureRow.placeholder.themedRow()
                }
            }
            .accessibilityLabel("Loading fixtures")
        case .failed:
            Section {
                HStack {
                    Text("Couldn't load fixtures")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { Task { await model.reload() } }
                }
                .frame(minHeight: 44)
                .themedRow()
            }
        case .loaded:
            if model.fixtures.isEmpty {
                Section {
                    Text("No matches this gameweek.")
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                        .themedRow()
                }
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.fixtures) { fixture in
                        FixtureRow(fixture: fixture, teams: lookups.teams).themedRow()
                    }
                } header: {
                    // As written, not the grouped style's small capitals.
                    Text(Self.title(for: day.day))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .textCase(nil)
                }
            }
            if !postponed.isEmpty {
                Section("Postponed") {
                    ForEach(postponed) { fixture in
                        FixtureRow(fixture: fixture, teams: lookups.teams).themedRow()
                    }
                }
            }
        }
    }

    /// The gameweek centered between the arrows. Tapping it lists every gameweek.
    private func header(_ gameweek: Int) -> some View {
        let last = max(gameweeks.events.map(\.id).max() ?? gameweek, gameweek)
        let dates = Self.dates(of: model.fixtures)
        // Only one still to come: a past gameweek's deadline says nothing.
        let deadline = gameweeks.deadline(for: gameweek).flatMap { $0 > .now ? $0 : nil }?
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        return HStack(spacing: 0) {
            arrow("chevron.left", label: "Previous gameweek", to: gameweek - 1, last: last)

            Menu {
                Picker("Gameweek", selection: Binding(get: { gameweek }, set: { select($0) })) {
                    ForEach(1...last, id: \.self) { number in
                        Text(number == gameweeks.current ? "Gameweek \(number) (current)" : "Gameweek \(number)")
                            .tag(number)
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Text("Gameweek \(gameweek)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.text)
                    if let dates {
                        Text(dates)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                    }
                    if let deadline {
                        Text("Deadline \(deadline)")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Gameweek \(gameweek)")
            .accessibilityValue([dates, deadline.map { "deadline \($0)" }].compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint("Choose a gameweek")
            .accessibilityAddTraits(.isHeader)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: if gameweek < last { select(gameweek + 1) }
                case .decrement: if gameweek > 1 { select(gameweek - 1) }
                @unknown default: break
                }
            }

            arrow("chevron.right", label: "Next gameweek", to: gameweek + 1, last: last)
        }
        // The arrows' glyphs sit near the card's edges.
        .padding(.horizontal, -10)
        .sensoryFeedback(.selection, trigger: gameweek)
    }

    private func arrow(_ systemImage: String, label: String, to target: Int, last: Int) -> some View {
        let isEnabled = (1...last).contains(target)
        return Button {
            select(target)
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isEnabled ? Theme.accent : Theme.border)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func select(_ gameweek: Int) {
        Task { await model.select(gameweek) }
    }

    /// "Today", "Tomorrow", or "Saturday, November 21" in the user's locale.
    nonisolated static func title(for day: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        var style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        style.timeZone = calendar.timeZone
        return day.formatted(style)
    }

    /// "Nov 21 – 23": the first to the last kickoff day. Nil with no kickoff times.
    nonisolated static func dates(of fixtures: [Fixture], calendar: Calendar = .current) -> String? {
        let kickoffs = fixtures.compactMap(\.kickoffTime)
        guard let first = kickoffs.min(), let last = kickoffs.max() else { return nil }
        var style = Date.IntervalFormatStyle().month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        return style.format(first..<last)
    }
}

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

#Preview {
    GameweekView(isSelected: true)
        .environmentObject(GameweekStore())
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
