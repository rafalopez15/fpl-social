//
//  TeamsAndFixturesStore.swift
//  FPL
//

import Foundation

/// Teams and upcoming fixtures for every screen that shows players: team short
/// names on rows, and the stats popover's fixtures. One shared copy, loaded once;
/// a failure only hides team names or fixtures, and the next `loadIfNeeded()` tries again.
@MainActor
final class TeamsAndFixturesStore: ObservableObject {
    /// The players list and Profile's squad both read this one.
    static let shared = TeamsAndFixturesStore()

    @Published private(set) var teams: [Int: Team] = [:]
    /// Nil until loaded, or when there are no fixtures to show.
    @Published private(set) var schedule: FixtureSchedule?

    private let client: FPLAPIClient
    /// Gameweeks come from here rather than a request of this store's own.
    private let gameweeks: GameweekStore
    private var fixtures: RecentFixtures?
    private var runningFixtures: Task<[Fixture]?, Never>?

    private struct RecentFixtures {
        let fixtures: [Fixture]
        let fetchedAt: Date
    }

    init(client: FPLAPIClient = FPLAPIClient(), gameweeks: GameweekStore = .shared) {
        self.client = client
        self.gameweeks = gameweeks
    }

    func loadIfNeeded() async {
        async let teamsLoaded: Void = loadTeams()
        async let scheduleLoaded: Void = loadSchedule()
        _ = await (teamsLoaded, scheduleLoaded)
    }

    private func loadTeams() async {
        guard teams.isEmpty, let fetched = try? await client.teams() else { return }
        teams = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func loadSchedule() async {
        guard schedule == nil else { return }
        async let fixtures = upcomingFixtures()
        // Not loadIfNeeded alone: between seasons there's no current gameweek, and that
        // would reload them on every call.
        if gameweeks.events.isEmpty { await gameweeks.loadIfNeeded() }
        guard let fixtures = await fixtures, !gameweeks.events.isEmpty else { return }
        schedule = FixtureSchedule(fixtures: fixtures, events: gameweeks.events)
    }

    /// Upcoming fixtures, also for live points' "yet to play". Ones fetched in the last
    /// 10 seconds are reused, so the schedule and live points share one request at launch;
    /// after that a refresh fetches them again, since matches start. Nil if it failed.
    func upcomingFixtures() async -> [Fixture]? {
        if let fixtures, fixtures.fetchedAt.timeIntervalSinceNow > -10 { return fixtures.fixtures }
        if let runningFixtures { return await runningFixtures.value }
        let fetch = Task { try? await client.upcomingFixtures() }
        runningFixtures = fetch
        defer { runningFixtures = nil }
        let fetched = await fetch.value
        if let fetched { fixtures = RecentFixtures(fixtures: fetched, fetchedAt: .now) }
        return fetched
    }
}
