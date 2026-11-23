//
//  GameweekExtrasTests.swift
//  FPLTests
//

import Foundation
import Testing
@testable import FPL

/// The Gameweek tab around its matches: your players in a match, a team's next
/// fixtures and the deadline countdown.
@MainActor
struct GameweekExtrasTests {
    private typealias Base = GameweekFixturesTests

    // MARK: Your players

    static func player(_ id: Int, team: Int) throws -> Element {
        let json = #"{"id": \#(id), "web_name": "Player \#(id)", "team": \#(team), "element_type": 3, "now_cost": 50, "status": "a"}"#
        return try JSONDecoder.fplAPI.decode(Element.self, from: Data(json.utf8))
    }

    @Test func countsYourStartersInAMatch() throws {
        // `fixture` is team 1 at home to team 2.
        let players = try Dictionary(uniqueKeysWithValues: [(7, 1), (8, 2), (9, 3), (10, 2)].map {
            ($0.0, try Self.player($0.0, team: $0.1))
        })
        let squad = ManagerPicks(picks: [.init(element: 10, position: 13), .init(element: 7, position: 4),
                                         .init(element: 9, position: 1), .init(element: 8, position: 2),
                                         .init(element: 99, position: 3)])
        // Player 10 is on the bench, so he doesn't count.
        #expect(squad.players(in: Base.upcoming, from: players).map(\.id) == [8, 7])
        #expect(squad.players(in: Base.upcoming, from: [:]).isEmpty)
        #expect(FixtureRow.countDescription(2) == "2 of your players")
    }

    @Test func countsEveryoneWhoScoresWithBenchBoost() throws {
        let players = try Dictionary(uniqueKeysWithValues: [7, 8, 10].map { ($0, try Self.player($0, team: 1)) })
        let squad = ManagerPicks(picks: [.init(element: 7, position: 4, multiplier: 2),
                                         .init(element: 8, position: 11, multiplier: 0),   // subbed off
                                         .init(element: 10, position: 13, multiplier: 1)]) // bench boosted
        #expect(squad.players(in: Base.upcoming, from: players).map(\.id) == [7, 10])
    }

    @Test func aSquadDoesntCountForEarlierGameweeks() {
        let squad = ManagerPicks(picks: [], entryHistory: .init(event: 10))
        #expect(!squad.applies(to: 9))
        #expect(squad.applies(to: 10))
        #expect(squad.applies(to: 11))
        #expect(ManagerPicks(picks: []).applies(to: 1))
    }

    // MARK: A team's next fixtures

    @Test func aTeamsNextFixturesAreTheSoonestStillToKickOff() throws {
        func match(_ id: Int, gameweek: Int?, home: Int, away: Int, day: Int?, started: Bool = false) -> Fixture {
            Fixture(id: id, event: gameweek, teamH: home, teamA: away, teamHDifficulty: 2, teamADifficulty: 4,
                    kickoffTime: day.map { Base.time(day: $0, hour: 15) }, started: started, finished: false,
                    teamHScore: nil, teamAScore: nil)
        }
        let fixtures = [match(1, gameweek: 10, home: 1, away: 2, day: 7, started: true),
                        match(2, gameweek: 10, home: 3, away: 1, day: 9),       // current gameweek, still to play
                        match(3, gameweek: 11, home: 1, away: 4, day: 21),
                        match(4, gameweek: 11, home: 5, away: 1, day: 24),      // a double
                        match(5, gameweek: 12, home: 6, away: 7, day: 28),      // someone else's
                        match(6, gameweek: nil, home: 1, away: 8, day: nil),    // postponed, no gameweek
                        match(7, gameweek: 12, home: 1, away: 9, day: 28),
                        match(8, gameweek: 13, home: 10, away: 1, day: 29),
                        match(9, gameweek: 14, home: 1, away: 11, day: 30)]
        var next = Self.event(11, deadline: Base.time(day: 20, hour: 11))
        next = Event(id: 11, name: next.name, deadlineTime: next.deadlineTime, finished: false, isCurrent: false, isNext: true)
        let schedule = try #require(FixtureSchedule(fixtures: fixtures, events: [next]))

        let coming = schedule.next(for: 1)
        #expect(coming.map(\.id) == [2, 3, 4, 7, 8])
        #expect(coming.map(\.gameweek) == [10, 11, 11, 12, 13])
        #expect(coming[0].fixture == TeamFixture(id: 2, opponent: 3, isHome: false, difficulty: 4))
        #expect(coming[1].fixture == TeamFixture(id: 3, opponent: 4, isHome: true, difficulty: 2))
        #expect(schedule.next(for: 99).isEmpty)
    }

    // MARK: Deadline countdown

    static func event(_ id: Int, deadline: Date) -> Event {
        Event(id: id, name: "Gameweek \(id)", deadlineTime: deadline, finished: false, isCurrent: false, isNext: false)
    }

    @Test func theCountdownShortensItsUnitsAsTheDeadlineNears() {
        let countdown = DeadlineCountdown(gameweek: 10, deadline: Base.time(day: 6, hour: 13, minute: 30))
        func left(day: Int, hour: Int, minute: Int = 0) -> String {
            countdown.remaining(now: Base.time(day: day, hour: hour, minute: minute))
        }
        #expect(left(day: 4, hour: 20, minute: 30) == "1d 17h")
        #expect(left(day: 5, hour: 13, minute: 30) == "1d 0h")
        #expect(left(day: 5, hour: 13, minute: 31) == "23h 59m")
        #expect(left(day: 6, hour: 8, minute: 18) == "5h 12m")
        #expect(left(day: 6, hour: 12, minute: 30) == "1h 0m")
        #expect(left(day: 6, hour: 12, minute: 48) == "42m")
        #expect(countdown.remaining(now: countdown.deadline - 30) == "<1m")
    }

    @Test func theCountdownWarnsUnderADay() {
        let countdown = DeadlineCountdown(gameweek: 10, deadline: Base.time(day: 6, hour: 13, minute: 30))
        #expect(!countdown.isSoon(now: Base.time(day: 5, hour: 13, minute: 30)))
        #expect(countdown.isSoon(now: Base.time(day: 5, hour: 13, minute: 31)))
    }

    @Test func theCountdownMovesToTheNextDeadlineAndEndsWithTheSeason() {
        let events = [Self.event(10, deadline: Base.time(day: 6, hour: 13, minute: 30)),
                      Self.event(11, deadline: Base.time(day: 21, hour: 11)),
                      Self.event(9, deadline: Base.time(day: 1, hour: 11))]
        #expect(DeadlineCountdown.next(in: events, now: Base.time(day: 4, hour: 9))?.gameweek == 10)
        // At the deadline itself it's passed.
        #expect(DeadlineCountdown.next(in: events, now: Base.time(day: 6, hour: 13, minute: 30))?.gameweek == 11)
        #expect(DeadlineCountdown.next(in: events, now: Base.time(day: 21, hour: 11)) == nil)
        #expect(DeadlineCountdown.next(in: [], now: Base.time(day: 4, hour: 9)) == nil)
    }

    @Test func theCountdownsLineAndVoiceOverText() {
        let countdown = DeadlineCountdown(gameweek: 10, deadline: Base.time(day: 6, hour: 13, minute: 30))
        let us = Locale(identifier: "en_US")
        let text = countdown.text(now: Base.time(day: 4, hour: 20, minute: 30), timeZone: Base.utc, locale: us)
        #expect(text.hasPrefix("Gameweek 10 deadline · Fri, Nov 6"))
        #expect(text.contains("1:30") && text.hasSuffix(" · 1d 17h"))

        let spoken = countdown.spokenText(now: Base.time(day: 4, hour: 20, minute: 30), timeZone: Base.utc, locale: us)
        #expect(spoken.hasSuffix(", in 1 day, 17 hours"))
        let soon = countdown.spokenText(now: Base.time(day: 6, hour: 8, minute: 18), timeZone: Base.utc, locale: us)
        #expect(soon.hasSuffix(", in 5 hours, 12 minutes"))
    }
}
