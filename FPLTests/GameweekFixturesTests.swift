//
//  GameweekFixturesTests.swift
//  FPLTests
//

import Foundation
import Testing
@testable import FPL

/// The Gameweek tab: a match's state, grouping by day, which gameweek opens, and
/// `GameweekFixturesModel` against fixtures handed to it.
@MainActor
struct GameweekFixturesTests {
    static let utc = TimeZone(identifier: "UTC")!

    /// A time on 7 November 2026, UTC.
    static func time(day: Int = 7, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    static func fixture(_ id: Int, kickoff: Date? = time(hour: 15), started: Bool = false, finished: Bool = false,
                        score: (Int, Int)? = nil, minutes: Int? = 0, finishedProvisional: Bool? = false) -> Fixture {
        Fixture(id: id, event: 10, teamH: 1, teamA: 2, teamHDifficulty: 3, teamADifficulty: 3,
                kickoffTime: kickoff, started: started, finished: finished,
                teamHScore: score?.0, teamAScore: score?.1, minutes: minutes, finishedProvisional: finishedProvisional)
    }

    static let played = fixture(1, started: true, score: (2, 1), minutes: 90, finishedProvisional: true)
    static let live = fixture(2, started: true, score: (1, 0), minutes: 67)
    static let upcoming = fixture(3)
    static let postponed = fixture(4, kickoff: nil)

    struct Failure: Error {}

    // MARK: Decoding

    @Test func decodesTheLiveFieldsAndDoesWithoutThem() throws {
        let json = """
        [{"id": 1, "event": 10, "team_h": 1, "team_a": 2, "team_h_difficulty": 2, "team_a_difficulty": 4,
          "kickoff_time": "2026-11-07T15:00:00Z", "started": true, "finished": false,
          "team_h_score": 2, "team_a_score": 1, "minutes": 67, "finished_provisional": false},
         {"id": 2, "event": 10, "team_h": 3, "team_a": 4, "team_h_difficulty": 2, "team_a_difficulty": 4,
          "kickoff_time": null, "started": false, "finished": false, "team_h_score": null, "team_a_score": null}]
        """
        let fixtures = try JSONDecoder.fplAPI.decode([Fixture].self, from: Data(json.utf8))
        #expect(fixtures[0].minutes == 67)
        #expect(fixtures[0].finishedProvisional == false)
        #expect(fixtures[0].matchState == .live(minute: 67))
        // `/api/fixtures` sends neither field.
        #expect(fixtures[1].minutes == nil)
        #expect(fixtures[1].matchState == .postponed)
    }

    // MARK: Match state

    @Test func matchState() {
        #expect(Self.upcoming.matchState == .notStarted)
        #expect(Self.live.matchState == .live(minute: 67))
        #expect(Self.played.matchState == .finished)
        #expect(Self.postponed.matchState == .postponed)
    }

    @Test func fullTimeCountsBeforeFPLConfirmsTheMatch() {
        // `finished` lags a day or more for bonus points.
        let fullTime = Self.fixture(1, started: true, finished: false, minutes: 90, finishedProvisional: true)
        #expect(fullTime.matchState == .finished)
        // The stored list has only `finished`.
        let stored = Self.fixture(2, started: true, finished: true, minutes: nil, finishedProvisional: nil)
        #expect(stored.matchState == .finished)
        let storedInPlay = Self.fixture(3, started: true, minutes: nil, finishedProvisional: nil)
        #expect(storedInPlay.matchState == .live(minute: 0))
    }

    @Test func voiceOverReadsEachState() {
        func read(_ fixture: Fixture) -> String {
            FixtureRow.description(of: fixture, home: "Arsenal", away: "Chelsea", timeZone: Self.utc)
        }
        #expect(read(Self.upcoming).hasPrefix("Arsenal v Chelsea, kicks off 3:00"))
        #expect(read(Self.live) == "Arsenal 1, Chelsea 0, live, 67 minutes")
        #expect(read(Self.played) == "Arsenal 2, Chelsea 1, full time")
        #expect(read(Self.postponed) == "Arsenal v Chelsea, postponed")
    }

    // MARK: Days

    @Test func groupsByDayInKickoffOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let saturdayLate = Self.fixture(1, kickoff: Self.time(hour: 17, minute: 30))
        let saturdayEarly = Self.fixture(2, kickoff: Self.time(hour: 12, minute: 30))
        let sunday = Self.fixture(3, kickoff: Self.time(day: 8, hour: 14))
        let sameTime = Self.fixture(0, kickoff: Self.time(hour: 17, minute: 30))

        let (days, postponed) = FixtureDay.days(for: [sunday, saturdayLate, Self.postponed, saturdayEarly, sameTime],
                                                calendar: calendar)
        #expect(days.map(\.day) == [Self.time(hour: 0), Self.time(day: 8, hour: 0)])
        // Ties go by id.
        #expect(days.map { $0.fixtures.map(\.id) } == [[2, 0, 1], [3]])
        #expect(postponed.map(\.id) == [4])
    }

    @Test func aLateKickoffFallsOnTheNextDayFurtherEast() throws {
        // 20:00 UTC on Saturday is 07:00 on Sunday in Sydney.
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let evening = Self.fixture(1, kickoff: Self.time(hour: 20))
        let lunchtime = Self.fixture(2, kickoff: Self.time(hour: 2))
        let days = FixtureDay.days(for: [evening, lunchtime], calendar: sydney).days
        #expect(days.map { $0.fixtures.map(\.id) } == [[2], [1]])
        #expect(sydney.component(.day, from: days[1].day) == 8)
    }

    @Test func dayTitlesAndTheGameweeksDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let saturday = Self.time(hour: 0)
        #expect(GameweekView.title(for: saturday, now: Self.time(hour: 9), calendar: calendar) == "Today")
        #expect(GameweekView.title(for: saturday, now: Self.time(day: 6, hour: 23), calendar: calendar) == "Tomorrow")
        let earlier = GameweekView.title(for: saturday, now: Self.time(day: 2, hour: 9), calendar: calendar)
        #expect(earlier.contains("Saturday") && earlier.contains("November") && earlier.contains("7"))

        let dates = GameweekView.dates(of: [Self.fixture(1, kickoff: Self.time(hour: 15)),
                                            Self.fixture(2, kickoff: Self.time(day: 9, hour: 20)),
                                            Self.postponed], calendar: calendar)
        #expect(dates?.contains("7") == true && dates?.contains("9") == true)
        #expect(GameweekView.dates(of: [Self.postponed], calendar: calendar) == nil)
    }

    // MARK: Which gameweek opens

    @Test func opensOnTheCurrentGameweekUntilEveryMatchIsPlayed() {
        #expect(Fixture.gameweekToOpen(current: 10, next: 11, currentFixtures: [Self.played, Self.live]) == 10)
        #expect(Fixture.gameweekToOpen(current: 10, next: 11, currentFixtures: [Self.played, Self.upcoming]) == 10)
        #expect(Fixture.gameweekToOpen(current: 10, next: 11, currentFixtures: [Self.played]) == 11)
        // A postponed match doesn't hold the gameweek open.
        #expect(Fixture.gameweekToOpen(current: 10, next: 11, currentFixtures: [Self.played, Self.postponed]) == 11)
        // Nothing to go on, or the season's last gameweek.
        #expect(Fixture.gameweekToOpen(current: 10, next: 11, currentFixtures: []) == 10)
        #expect(Fixture.gameweekToOpen(current: 38, next: nil, currentFixtures: [Self.played]) == 38)
    }

    // MARK: The model

    @Test func opensOnTheNextGameweekOnceTheCurrentOneIsOver() async {
        let model = GameweekFixturesModel { $0 == 10 ? [Self.played] : [Self.upcoming] }
        await model.open(current: 10, next: 11)
        #expect(model.gameweek == 11)
        #expect(model.state == .loaded)
        #expect(model.fixtures == [Self.upcoming])

        // Only the first call picks a gameweek.
        await model.select(3)
        await model.open(current: 10, next: 11)
        #expect(model.gameweek == 3)
    }

    @Test func staysOnTheCurrentGameweekWhenItCantLoad() async {
        let model = GameweekFixturesModel { _ in throw Failure() }
        await model.open(current: 10, next: 11)
        #expect(model.gameweek == 10)
        #expect(model.state == .failed)
    }

    @Test func aGameweekWithNoMatchesIsLoadedAndEmpty() async {
        // The API's answer when every match is postponed out of the gameweek.
        let model = GameweekFixturesModel { _ in [] }
        await model.select(7)
        #expect(model.state == .loaded)
        #expect(model.fixtures.isEmpty)
    }

    @Test(arguments: ["Event not found", "Not Found"])
    func a404IsAFailureNotAnEmptyGameweek(detail: String) async {
        // A gameweek the API doesn't have, or a backend without the route.
        let model = GameweekFixturesModel { _ in throw FPLAPIClient.APIError.notFound(detail) }
        await model.select(10)
        #expect(model.state == .failed)
    }

    @Test func aFailedReloadKeepsWhatsShown() async {
        var fails = false
        let model = GameweekFixturesModel { _ in
            if fails { throw Failure() }
            return [Self.live]
        }
        await model.select(10)
        fails = true
        #expect(await model.reload() == false)
        #expect(model.state == .loaded)
        #expect(model.fixtures == [Self.live])

        // Stepping away and back shows it again while the latest loads.
        await model.select(11)
        #expect(model.state == .failed)
        await model.select(10)
        #expect(model.state == .loaded)
        #expect(model.fixtures == [Self.live])
    }

    @Test func retryingAFailedGameweekLoadsIt() async {
        var fails = true
        let model = GameweekFixturesModel { _ in
            if fails { throw Failure() }
            return [Self.upcoming]
        }
        await model.select(10)
        #expect(model.state == .failed)
        fails = false
        #expect(await model.reload())
        #expect(model.state == .loaded)
        #expect(model.fixtures == [Self.upcoming])
    }

    @Test func onlyTheNewestSelectionIsShown() async {
        // Gameweek 10 answers after gameweek 11 was picked.
        let model = GameweekFixturesModel { gameweek in
            if gameweek == 10 { try? await Task.sleep(for: .milliseconds(150)) }
            return [Self.fixture(gameweek)]
        }
        async let slow: Void = model.select(10)
        try? await Task.sleep(for: .milliseconds(20))
        await model.select(11)
        await slow
        #expect(model.gameweek == 11)
        #expect(model.fixtures.map(\.id) == [11])
    }
}
