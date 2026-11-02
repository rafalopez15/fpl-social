//
//  FPLTests.swift
//  FPLTests
//
//  Created by Rafael Lopez on 11/4/24.
//

import Foundation
import Testing
@testable import FPL

struct ElementDecodingTests {

    /// `GET /api/elements/1` example response from the fplAPI handoff.
    static let fixture = """
    {
      "id": 1,
      "web_name": "Raya",
      "team": 1,
      "element_type": 1,
      "now_cost": 62,
      "status": "a",
      "code": 154561,
      "first_name": "David",
      "second_name": "Raya Martín",
      "team_code": 3,
      "photo": "154561.jpg",
      "news": "",
      "news_added": null,
      "chance_of_playing_next_round": null,
      "chance_of_playing_this_round": null,
      "cost_change_event": 0,
      "cost_change_start": 2,
      "selected_by_percent": 46.3,
      "transfers_in_event": 13365,
      "transfers_out_event": 2478,
      "total_points": 49,
      "event_points": 0,
      "points_per_game": 6.1,
      "form": 4.8,
      "ep_next": 4.8,
      "minutes": 720,
      "starts": 8,
      "goals_scored": 0,
      "assists": 0,
      "clean_sheets": 5,
      "goals_conceded": 5,
      "saves": 18,
      "bonus": 6,
      "yellow_cards": 0,
      "red_cards": 0,
      "expected_goals": 0.0,
      "expected_assists": 0.01,
      "expected_goal_involvements": 0.01,
      "expected_goals_conceded": 6.18,
      "ict_index": 16.7
    }
    """

    static let requiredKeys = ["id", "web_name", "team", "element_type", "now_cost", "status"]

    static func fixtureObject() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(fixture.utf8)) as? [String: Any])
    }

    static func decode(_ object: [String: Any]) throws -> Element {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder.fplAPI.decode(Element.self, from: data)
    }

    @Test func decodesExampleResponse() throws {
        let element = try JSONDecoder.fplAPI.decode(Element.self, from: Data(Self.fixture.utf8))

        #expect(element.id == 1)
        #expect(element.webName == "Raya")
        #expect(element.team == 1)
        #expect(element.position == .goalkeeper)
        #expect(element.nowCost == 62)
        #expect(element.price == 6.2)
        #expect(element.status == .available)
        #expect(element.fullName == "David Raya Martín")
        #expect(element.selectedByPercent == 46.3)
        #expect(element.totalPoints == 49)
        #expect(element.expectedGoalsConceded == 6.18)
        #expect(element.newsAdded == nil)
        #expect(element.currentNews == nil)
    }

    @Test func decodesWithOptionalFieldsNull() throws {
        var object = try Self.fixtureObject()
        for key in object.keys where !Self.requiredKeys.contains(key) {
            object[key] = NSNull()
        }
        let element = try Self.decode(object)
        #expect(element.firstName == nil)
        #expect(element.totalPoints == nil)
        #expect(element.fullName == "Raya")
    }

    @Test func decodesWithOptionalFieldsMissing() throws {
        let object = try Self.fixtureObject().filter { Self.requiredKeys.contains($0.key) }
        let element = try Self.decode(object)
        #expect(element.id == 1)
        #expect(element.ictIndex == nil)
    }

    @Test(arguments: requiredKeys)
    func failsWhenRequiredFieldMissing(key: String) throws {
        var object = try Self.fixtureObject()
        object.removeValue(forKey: key)
        #expect(throws: DecodingError.self) { try Self.decode(object) }
    }

    @Test func decodesNewsAddedWithFractionalSeconds() throws {
        var object = try Self.fixtureObject()
        object["news_added"] = "2026-10-20T10:30:12.123456Z"
        let element = try Self.decode(object)

        let date = try #require(element.newsAdded)
        let wholeSeconds = try #require(ISO8601DateFormatter().date(from: "2026-10-20T10:30:12Z"))
        #expect(abs(date.timeIntervalSince(wholeSeconds) - 0.123) < 0.001)
    }

    @Test(arguments: [
        ("a", Element.Status.available), ("d", .doubtful), ("i", .injured),
        ("s", .suspended), ("u", .unavailable), ("n", .notEligible), ("x", .unknown),
    ])
    func decodesStatus(raw: String, expected: Element.Status) throws {
        var object = try Self.fixtureObject()
        object["status"] = raw
        #expect(try Self.decode(object).status == expected)
    }
}

struct ElementAvailabilityTests {

    static func element(status: String, chance: Int?, news: String = "", canSelect: Bool? = nil, removed: Bool? = nil) throws -> Element {
        var object = try ElementDecodingTests.fixtureObject()
        object["status"] = status
        object["chance_of_playing_next_round"] = chance ?? NSNull()
        object["news"] = news
        if let canSelect { object["can_select"] = canSelect }
        if let removed { object["removed"] = removed }
        return try ElementDecodingTests.decode(object)
    }

    @Test(arguments: [25, 50, 75])
    func percentageChanceIsDoubtful(chance: Int) throws {
        let element = try Self.element(status: "d", chance: chance, news: "Knock - \(chance)% chance of playing")
        #expect(element.availabilityFlag == .doubtful)
        #expect(element.availabilityDescription == "\(chance)% chance of playing")
    }

    @Test(arguments: [
        ("i", "Thigh injury - Unknown return date"),
        ("i", "Hamstring injury - Expected back 22 Nov"),
        ("s", "Suspended until 2 Dec"),
    ])
    func zeroChanceIsOut(status: String, news: String) throws {
        #expect(try Self.element(status: status, chance: 0, news: news).availabilityFlag == .out)
    }

    @Test func unknownReturnDateIsOutEvenWithoutAChance() throws {
        let element = try Self.element(status: "d", chance: nil, news: "Knee injury - Unknown return date")
        #expect(element.availabilityFlag == .out)
    }

    @Test func availablePlayersAreNotFlagged() throws {
        #expect(try Self.element(status: "a", chance: nil).availabilityFlag == nil)
        #expect(try Self.element(status: "a", chance: 100).availabilityFlag == nil)
    }

    @Test func fallsBackToStatusWithoutAChance() throws {
        #expect(try Self.element(status: "d", chance: nil).availabilityFlag == .doubtful)
        #expect(try Self.element(status: "i", chance: nil).availabilityFlag == .out)
        #expect(try Self.element(status: "x", chance: nil).availabilityFlag == nil)
    }

    @Test func playersWhoLeftAreNotSelectable() throws {
        let left = try Self.element(status: "u", chance: 0, news: "Has joined Al Hilal permanently", canSelect: false)
        #expect(!left.isSelectable)
        #expect(try Self.element(status: "i", chance: 0, canSelect: true).isSelectable)
    }

    @Test func statusAloneDoesNotHidePlayers() throws {
        #expect(try Self.element(status: "u", chance: 0).isSelectable)
        #expect(try Self.element(status: "u", chance: 0, canSelect: true).isSelectable)
    }

    @Test func removedPlayersAreNotSelectable() throws {
        #expect(!(try Self.element(status: "a", chance: nil, canSelect: true, removed: true).isSelectable))
        #expect(try Self.element(status: "a", chance: nil, canSelect: true, removed: false).isSelectable)
    }

    @Test func decodesTransferFlags() throws {
        var object = try ElementDecodingTests.fixtureObject()
        object["can_select"] = true
        object["can_transact"] = false
        object["removed"] = false
        let element = try ElementDecodingTests.decode(object)
        #expect(element.canSelect == true)
        #expect(element.canTransact == false)
        #expect(element.removed == false)
    }
}

struct ElementSortTests {

    static func element(price: Int, points: Int?, goals: Int?, assists: Int?) throws -> Element {
        var object = try ElementDecodingTests.fixtureObject()
        object["now_cost"] = price
        object["total_points"] = points ?? NSNull()
        object["goals_scored"] = goals ?? NSNull()
        object["assists"] = assists ?? NSNull()
        return try ElementDecodingTests.decode(object)
    }

    @Test func sortValuesReadTheMatchingField() throws {
        let element = try Self.element(price: 62, points: 80, goals: 3, assists: 5)
        #expect(ElementSort.points.value(for: element) == 80)
        #expect(ElementSort.price.value(for: element) == 6.2)
        #expect(ElementSort.goals.value(for: element) == 3)
        #expect(ElementSort.assists.value(for: element) == 5)
    }

    @Test func missingStatsSortAsZero() throws {
        let element = try Self.element(price: 45, points: nil, goals: nil, assists: nil)
        #expect(ElementSort.points.value(for: element) == 0)
        #expect(ElementSort.goals.value(for: element) == 0)
        #expect(ElementSort.assists.value(for: element) == 0)
    }
}

struct FixtureDecodingTests {

    /// One fixture from `GET /api/fixtures?started=false`.
    static let response = """
    [
      {"id": 89, "event": 9, "team_h": 17, "team_a": 9, "team_h_difficulty": 3, "team_a_difficulty": 4,
       "kickoff_time": "2026-11-02T20:00:00Z", "started": false, "finished": false,
       "team_h_score": null, "team_a_score": null},
      {"id": 300, "event": null, "team_h": 1, "team_a": 2, "team_h_difficulty": 2, "team_a_difficulty": 5,
       "kickoff_time": null, "started": false, "finished": false,
       "team_h_score": null, "team_a_score": null}
    ]
    """

    @Test func decodesFixtures() throws {
        let fixtures = try JSONDecoder.fplAPI.decode([Fixture].self, from: Data(Self.response.utf8))
        #expect(fixtures.count == 2)

        let first = fixtures[0]
        #expect(first.event == 9)
        #expect(first.teamH == 17 && first.teamA == 9)
        #expect(first.teamHDifficulty == 3 && first.teamADifficulty == 4)
        #expect(first.kickoffTime == ISO8601DateFormatter().date(from: "2026-11-02T20:00:00Z"))
        #expect(!first.started && !first.finished)
        #expect(first.teamHScore == nil)

        // Postponed: no gameweek or kickoff yet.
        #expect(fixtures[1].event == nil)
        #expect(fixtures[1].kickoffTime == nil)
    }

    @Test func decodesEventsIgnoringExtraFields() throws {
        let json = """
        [{"id": 10, "name": "Gameweek 10", "deadline_time": "2026-11-07T11:00:00Z",
          "deadline_time_epoch": 1793876400, "finished": false, "data_checked": false,
          "is_previous": false, "is_current": false, "is_next": true,
          "top_element_info": null, "chip_plays": []}]
        """
        let events = try JSONDecoder.fplAPI.decode([Event].self, from: Data(json.utf8))
        #expect(events.first?.id == 10)
        #expect(events.first?.isNext == true)
        #expect(events.first?.isCurrent == false)
    }
}

struct FixtureScheduleTests {

    static func fixture(_ id: Int, gw: Int?, home: Int, away: Int,
                        homeDifficulty: Int = 2, awayDifficulty: Int = 4,
                        started: Bool = false) -> Fixture {
        Fixture(id: id, event: gw, teamH: home, teamA: away,
                teamHDifficulty: homeDifficulty, teamADifficulty: awayDifficulty,
                kickoffTime: nil, started: started, finished: false,
                teamHScore: nil, teamAScore: nil)
    }

    /// A 38-gameweek season with `next` as the next gameweek.
    static func events(next: Int) -> [Event] {
        (1...38).map { id in
            Event(id: id, name: "Gameweek \(id)", deadlineTime: .now, finished: id < next - 1,
                  isCurrent: id == next - 1, isNext: id == next)
        }
    }

    @Test func nextThreeGameweeksFromThePlayersSide() throws {
        let schedule = try #require(FixtureSchedule(fixtures: [
            Self.fixture(1, gw: 10, home: 1, away: 5, homeDifficulty: 2, awayDifficulty: 4),
            Self.fixture(2, gw: 11, home: 6, away: 1, homeDifficulty: 3, awayDifficulty: 5),
            Self.fixture(3, gw: 12, home: 1, away: 7),
            Self.fixture(4, gw: 13, home: 8, away: 1),
            Self.fixture(5, gw: 10, home: 2, away: 3),
        ], events: Self.events(next: 10)))

        let upcoming = schedule.upcoming(for: 1)
        #expect(upcoming.map(\.gameweek) == [10, 11, 12])
        #expect(upcoming[0].fixtures == [TeamFixture(id: 1, opponent: 5, isHome: true, difficulty: 2)])
        #expect(upcoming[1].fixtures == [TeamFixture(id: 2, opponent: 6, isHome: false, difficulty: 5)])
    }

    @Test func blankGameweekIsEmptyNotSkipped() throws {
        let schedule = try #require(FixtureSchedule(fixtures: [
            Self.fixture(1, gw: 10, home: 1, away: 5),
            Self.fixture(2, gw: 12, home: 1, away: 6),
            Self.fixture(3, gw: 13, home: 1, away: 7),
        ], events: Self.events(next: 10)))

        let upcoming = schedule.upcoming(for: 1)
        #expect(upcoming.map(\.gameweek) == [10, 11, 12])
        #expect(upcoming[1].fixtures.isEmpty)
    }

    @Test func doubleGameweekShowsBothFixtures() throws {
        let schedule = try #require(FixtureSchedule(fixtures: [
            Self.fixture(1, gw: 10, home: 1, away: 5),
            Self.fixture(2, gw: 10, home: 6, away: 1),
        ], events: Self.events(next: 10)))

        #expect(schedule.upcoming(for: 1)[0].fixtures.map(\.opponent) == [5, 6])
    }

    @Test func postponedAndStartedMatchesAreLeftOut() throws {
        let schedule = try #require(FixtureSchedule(fixtures: [
            Self.fixture(1, gw: nil, home: 1, away: 5),
            Self.fixture(2, gw: 10, home: 1, away: 6, started: true),
            Self.fixture(3, gw: 11, home: 1, away: 7),
        ], events: Self.events(next: 10)))

        let upcoming = schedule.upcoming(for: 1)
        #expect(upcoming[0].fixtures.isEmpty)
        #expect(upcoming[1].fixtures.map(\.opponent) == [7])
    }

    @Test func endOfSeasonShowsOnlyRemainingGameweeks() throws {
        let schedule = try #require(FixtureSchedule(fixtures: [
            Self.fixture(1, gw: 37, home: 1, away: 5),
            Self.fixture(2, gw: 38, home: 6, away: 1),
        ], events: Self.events(next: 37)))

        #expect(schedule.upcoming(for: 1).map(\.gameweek) == [37, 38])
    }

    @Test func noScheduleWithoutFixturesOrNextGameweek() {
        #expect(FixtureSchedule(fixtures: [], events: Self.events(next: 10)) == nil)

        let seasonOver = (1...38).map {
            Event(id: $0, name: "", deadlineTime: .now, finished: true, isCurrent: $0 == 38, isNext: false)
        }
        #expect(FixtureSchedule(fixtures: [Self.fixture(1, gw: 38, home: 1, away: 2)], events: seasonOver) == nil)
    }
}

struct NoteTests {

    static func date(_ day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
    }

    @Test func sectionsAreNewestGameweekFirstWithUntaggedLast() {
        let notes = [
            Note(text: "a", gameweek: 9, createdAt: Self.date(1)),
            Note(text: "b", gameweek: nil, createdAt: Self.date(2)),
            Note(text: "c", gameweek: 10, createdAt: Self.date(3)),
            Note(text: "d", gameweek: 10, createdAt: Self.date(4)),
        ]
        let sections = NoteSection.sections(for: notes)
        #expect(sections.map(\.gameweek) == [10, 9, nil])
        #expect(sections.map(\.title) == ["Gameweek 10", "Gameweek 9", "No gameweek"])
        // Newest note first within a gameweek.
        #expect(sections[0].notes.map(\.text) == ["d", "c"])
    }

    @Test func everyGameweekUpToTheCurrentOneGetsASection() {
        let notes = [
            Note(text: "a", gameweek: 2, createdAt: Self.date(1)),
            Note(text: "b", gameweek: nil, createdAt: Self.date(2)),
        ]
        let sections = NoteSection.sections(for: notes, currentGameweek: 4)
        #expect(sections.map(\.gameweek) == [4, 3, 2, 1, nil])
        #expect(sections.map(\.notes.count) == [0, 0, 1, 0, 1])
    }

    @Test func currentGameweekPrefersInProgressThenNext() {
        let midSeason = FixtureScheduleTests.events(next: 10)
        #expect(Event.currentGameweek(in: midSeason) == 9)

        let preSeason = (1...38).map {
            Event(id: $0, name: "", deadlineTime: .now, finished: false, isCurrent: false, isNext: $0 == 1)
        }
        #expect(Event.currentGameweek(in: preSeason) == 1)
        #expect(Event.currentGameweek(in: []) == nil)
    }

    @Test func notesFromPastGameweeksAreLocked() {
        #expect(Note(text: "", gameweek: 8).isLocked(currentGameweek: 9))
        #expect(!Note(text: "", gameweek: 9).isLocked(currentGameweek: 9))
        #expect(!Note(text: "", gameweek: nil).isLocked(currentGameweek: 9))
        #expect(!Note(text: "", gameweek: 8).isLocked(currentGameweek: nil))
    }

    @Test func undoRestoresTheDeletedNote() {
        let note = Note(text: "Holding Salah", gameweek: 7,
                        players: [NotePlayer(id: 2, webName: "M.Salah")], createdAt: Self.date(5))
        note.updatedAt = Self.date(6)

        let restored = DeletedNote(note).restored()
        #expect(restored.text == "Holding Salah")
        #expect(restored.gameweek == 7)
        #expect(restored.players == note.players)
        #expect(restored.createdAt == Self.date(5))
        #expect(restored.updatedAt == Self.date(6))
    }

    @Test func linkedPlayersAreKept() {
        let note = Note(text: "Watch his minutes", gameweek: 10, players: [NotePlayer(id: 7, webName: "Isak")])
        #expect(note.players.map(\.webName) == ["Isak"])
        #expect(note.updatedAt == note.createdAt)
    }
}
