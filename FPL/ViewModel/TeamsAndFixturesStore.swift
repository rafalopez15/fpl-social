//
//  TeamsAndFixturesStore.swift
//  FPL
//

import Foundation

/// Teams and upcoming fixtures for screens outside the Players tab that show
/// players: team short names on rows, and the stats popover's fixtures.
/// Loaded once; a failure only hides team names or fixtures, and the next
/// `loadIfNeeded()` tries again.
@MainActor
final class TeamsAndFixturesStore: ObservableObject {
    @Published private(set) var teams: [Int: Team] = [:]
    /// Nil until loaded, or when there are no fixtures to show.
    @Published private(set) var schedule: FixtureSchedule?

    private let client: FPLAPIClient

    init(client: FPLAPIClient = FPLAPIClient()) {
        self.client = client
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
        async let fixtures = client.upcomingFixtures()
        async let events = client.events()
        guard let fixtures = try? await fixtures, let events = try? await events else { return }
        schedule = FixtureSchedule(fixtures: fixtures, events: events)
    }
}
