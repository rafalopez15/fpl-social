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
}
