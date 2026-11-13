//
//  Fixture.swift
//  FPL
//

import Foundation

/// A Premier League match from `GET /api/fixtures`, or live from
/// `GET /api/events/{gw}/fixtures`.
struct Fixture: Codable, Identifiable, Hashable {
    let id: Int
    /// Gameweek. Nil while a postponed match hasn't been rescheduled.
    let event: Int?
    /// Home team id (1–20), matching `Element.team`.
    let teamH: Int
    /// Away team id (1–20).
    let teamA: Int
    /// FPL's 1–5 difficulty rating for the home team.
    let teamHDifficulty: Int
    /// FPL's 1–5 difficulty rating for the away team.
    let teamADifficulty: Int
    let kickoffTime: Date?
    /// True once the match has kicked off. Use this, not `finished`, to tell
    /// what's upcoming: FPL only sets `finished` once bonus points are
    /// confirmed, a day or more after the match.
    let started: Bool
    let finished: Bool
    let teamHScore: Int?
    let teamAScore: Int?
    /// Minutes played. Only the live endpoint sends it.
    var minutes: Int? = nil
    /// True at full time, a day or more before `finished`. Only the live endpoint sends it.
    var finishedProvisional: Bool? = nil
}

// MARK: - A gameweek's matches

extension Fixture {
    enum MatchState: Equatable {
        case notStarted
        case live(minute: Int)
        case finished
        /// No kickoff time yet.
        case postponed
    }

    /// Only for `/events/{gw}/fixtures`: the stored list has no `finishedProvisional`,
    /// so its matches would read as live until `finished`, a day or more after full time.
    var matchState: MatchState {
        guard kickoffTime != nil else { return .postponed }
        if finishedProvisional == true || finished { return .finished }
        return started ? .live(minute: minutes ?? 0) : .notStarted
    }

    /// True once every match with a kickoff time is over. False with none.
    static func allPlayed(_ fixtures: [Fixture]) -> Bool {
        let scheduled = fixtures.filter { $0.kickoffTime != nil }
        return !scheduled.isEmpty && scheduled.allSatisfy { $0.matchState == .finished }
    }

    /// The gameweek the Gameweek tab opens on: the current one, or the next once
    /// every match of the current one has been played.
    static func gameweekToOpen(current: Int, next: Int?, currentFixtures: [Fixture]) -> Int {
        guard let next, allPlayed(currentFixtures) else { return current }
        return next
    }
}

/// One day's matches in a gameweek, in kickoff order.
struct FixtureDay: Identifiable, Equatable {
    /// The start of the day in the user's time zone.
    let day: Date
    let fixtures: [Fixture]

    var id: Date { day }

    /// Matches grouped by the day they kick off in `calendar`'s time zone, earliest
    /// first, and the postponed ones (no kickoff time) apart.
    static func days(for fixtures: [Fixture], calendar: Calendar = .current) -> (days: [FixtureDay], postponed: [Fixture]) {
        let scheduled = fixtures.filter { $0.kickoffTime != nil }
            .sorted { ($0.kickoffTime!, $0.id) < ($1.kickoffTime!, $1.id) }
        let days = Dictionary(grouping: scheduled) { calendar.startOfDay(for: $0.kickoffTime!) }
            .map { FixtureDay(day: $0.key, fixtures: $0.value) }
            .sorted { $0.day < $1.day }
        return (days, fixtures.filter { $0.kickoffTime == nil })
    }
}

/// A gameweek from `GET /api/events`. Only the fields the app uses are decoded.
struct Event: Codable, Identifiable, Hashable {
    let id: Int
    /// e.g. "Gameweek 10"
    let name: String
    let deadlineTime: Date
    let finished: Bool
    let isCurrent: Bool
    /// The next gameweek to start. A gameweek already in progress is current, not next.
    let isNext: Bool
}

// MARK: - Upcoming fixtures

/// One team's side of a fixture: who they play, where, and how hard FPL rates it.
struct TeamFixture: Identifiable, Hashable {
    /// The fixture id.
    let id: Int
    let opponent: Int
    let isHome: Bool
    /// FPL's 1–5 difficulty from this team's side.
    let difficulty: Int
}

/// A team's fixtures in one gameweek: none (a blank), one, or two (a double).
struct GameweekFixtures: Identifiable, Hashable {
    let gameweek: Int
    let fixtures: [TeamFixture]

    var id: Int { gameweek }
}

/// Upcoming fixtures grouped by gameweek, for working out a team's next few gameweeks.
struct FixtureSchedule {
    /// The gameweek with `is_next`.
    let nextGameweek: Int
    /// The season's last gameweek.
    let lastGameweek: Int
    private let fixturesByGameweek: [Int: [Fixture]]

    /// Nil when there's nothing to show: no fixtures yet (e.g. right after a
    /// deploy) or no next gameweek (the season is over).
    init?(fixtures: [Fixture], events: [Event]) {
        guard let next = events.first(where: \.isNext)?.id,
              let last = events.map(\.id).max()
        else { return nil }

        // Postponed matches (no gameweek) and matches already kicked off are left out.
        let upcoming = fixtures.filter { !$0.started && $0.event != nil }
        guard !upcoming.isEmpty else { return nil }

        nextGameweek = next
        lastGameweek = last
        fixturesByGameweek = Dictionary(grouping: upcoming) { $0.event! }
    }

    /// The team's fixtures in the next `count` gameweeks, one entry per gameweek,
    /// including blanks. Fewer entries near the end of the season.
    func upcoming(for team: Int, count: Int = 3) -> [GameweekFixtures] {
        let end = min(nextGameweek + count - 1, lastGameweek)
        guard end >= nextGameweek else { return [] }

        return (nextGameweek...end).map { gameweek in
            let fixtures = (fixturesByGameweek[gameweek] ?? []).compactMap { fixture -> TeamFixture? in
                if fixture.teamH == team {
                    return TeamFixture(id: fixture.id, opponent: fixture.teamA, isHome: true,
                                       difficulty: fixture.teamHDifficulty)
                }
                if fixture.teamA == team {
                    return TeamFixture(id: fixture.id, opponent: fixture.teamH, isHome: false,
                                       difficulty: fixture.teamADifficulty)
                }
                return nil
            }
            return GameweekFixtures(gameweek: gameweek, fixtures: fixtures)
        }
    }
}
