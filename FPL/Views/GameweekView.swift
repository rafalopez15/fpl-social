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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var gameweeks: GameweekStore
    @EnvironmentObject private var linkedTeam: LinkedTeamStore
    @ObservedObject private var lookups = TeamsAndFixturesStore.shared
    @StateObject private var model = GameweekFixturesModel()
    @State private var isRefreshing = false
    /// The team whose next fixtures are up.
    @State private var teamShown: Team?

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
            .sheet(item: $teamShown) { team in
                TeamFixturesSheet(team: team, fixtures: lookups.schedule?.next(for: team.id) ?? [], teams: lookups.teams)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Theme.background)
            }
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
        // Only while the tab is on screen and a match is live or still to come, or FPL is down.
        .task(id: RefreshKey(isOn: isSelected && scenePhase == .active && model.refreshesItself,
                             gameweek: model.gameweek)) {
            guard isSelected, scenePhase == .active else { return }
            await refreshItself()
        }
    }

    /// Reloads the gameweek a minute after its last load, or at the next kickoff, for as
    /// long as this runs.
    private func refreshItself() async {
        while let delay = model.refreshDelay() {
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            await model.reload()
        }
    }

    private struct RefreshKey: Equatable {
        let isOn: Bool
        let gameweek: Int?
    }

    private func row(_ fixture: Fixture) -> some View {
        // The latest squad, from its own gameweek on. Nil with no team or squad.
        let squad: ManagerPicks? = if case .loaded(let picks) = linkedTeam.squad,
                                      model.gameweek.map(picks.applies) ?? true { picks } else { nil }
        return FixtureRow(fixture: fixture, teams: lookups.teams, isStale: model.staleAsOf != nil,
                          yourPlayers: squad?.players(in: fixture, from: linkedTeam.players),
                          onTeam: { teamShown = $0 })
            .themedRow()
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
                // Each minute, for the countdown.
                TimelineView(.everyMinute) { timeline in
                    header(gameweek, now: timeline.date)
                }
                .themedRow()
                if let staleAsOf = model.staleAsOf {
                    Label(Self.staleLine(asOf: staleAsOf), systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .themedRow()
                } else if model.couldntUpdate {
                    Label("Couldn't update", systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .themedRow()
                }
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
            // A failure shows the "Couldn't update" row, not a toast.
            await Task { await model.reload() }.value
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
                    ForEach(day.fixtures, content: row)
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
                    ForEach(postponed, content: row)
                }
            }
        }
    }

    /// The gameweek centered between the arrows. Tapping it lists every gameweek.
    private func header(_ gameweek: Int, now: Date) -> some View {
        let last = max(gameweeks.events.map(\.id).max() ?? gameweek, gameweek)
        let dates = Self.dates(of: model.fixtures)
        // The next deadline whichever gameweek is shown; nil after the season's last.
        let countdown = DeadlineCountdown.next(in: gameweeks.events, now: now)
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
                    if let countdown {
                        Text(countdown.text(now: now))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(countdown.isSoon(now: now) ? Theme.warning : Theme.secondaryText)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Gameweek \(gameweek)")
            .accessibilityValue([dates, countdown?.spokenText(now: now)].compactMap { $0 }.joined(separator: ", "))
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
}

extension GameweekView {
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

    /// "FPL is updating · showing scores as of 13:28", in the user's time zone.
    nonisolated static func staleLine(asOf date: Date, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return "FPL is updating · showing scores as of \(date.formatted(style))"
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

#Preview {
    GameweekView(isSelected: true)
        .environmentObject(GameweekStore())
        .environmentObject(LinkedTeamStore())
}
