//
//  FPLTests.swift
//  FPLTests
//
//  Created by Rafael Lopez on 11/4/24.
//

import Foundation
import os
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
        #expect(Note(text: "Hold", gameweek: 8).isLocked(currentGameweek: 9))
        #expect(!Note(text: "Hold", gameweek: 9).isLocked(currentGameweek: 9))
        #expect(!Note(text: "Hold", gameweek: nil).isLocked(currentGameweek: 9))
        #expect(!Note(text: "Hold", gameweek: 8).isLocked(currentGameweek: nil))
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

struct ManagerTests {

    /// `GET /api/managers/1`, trimmed.
    static let response = """
    {"id": 1, "name": "Solio Moose", "player_first_name": "Chris", "player_last_name": "Musson",
     "current_event": 9, "started_event": 1, "favourite_team": 14, "player_region_name": "England",
     "summary_overall_points": 563, "summary_overall_rank": 1571477,
     "summary_event_points": 55, "summary_event_rank": 1972509,
     "last_deadline_bank": 21, "last_deadline_value": 1022, "last_deadline_total_transfers": 6}
    """

    static func manager(_ json: String = response) throws -> Manager {
        try JSONDecoder.fplAPI.decode(Manager.self, from: Data(json.utf8))
    }

    @Test func decodesManager() throws {
        let manager = try Self.manager()
        #expect(manager.id == 1)
        #expect(manager.name == "Solio Moose")
        #expect(manager.managerName == "Chris Musson")
        #expect(manager.summaryOverallRank == 1_571_477)
        #expect(manager.lastDeadlineValue == 1022)
    }

    @Test func optionalFieldsCanBeNullOrMissing() throws {
        let manager = try Self.manager("""
        {"id": 2, "name": "New Team", "player_first_name": "Ana", "player_last_name": "",
         "current_event": null}
        """)
        #expect(manager.currentEvent == nil)
        #expect(manager.summaryOverallPoints == nil)
        #expect(manager.managerName == "Ana")
    }

    @Test(arguments: [
        ("1234567", "1234567"),
        ("12a3 4", "1234"),
        ("fantasy.premierleague.com/entry/1234567/event/9", "12345679"),
        ("123456789012", "1234567890"),
    ])
    func idFieldKeepsDigitsOnly(input: String, expected: String) {
        #expect(LinkTeamModel.digits(in: input) == expected)
    }

    @Test func lookupErrorsMapToMessages() {
        #expect(LinkError(FPLAPIClient.APIError.notFound("Manager not found")) == .notFound)
        #expect(LinkError(FPLAPIClient.APIError.dataUnavailable("FPL is unavailable right now")) == .fplUnavailable)
        #expect(LinkError(URLError(.notConnectedToInternet)) == .other)
        #expect(!LinkError.notFound.canRetry)
        #expect(LinkError.fplUnavailable.canRetry)
    }

    @MainActor @Test func linkSurvivesARestartAndUnlinks() throws {
        let suite = "FPLTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = LinkedTeamStore(defaults: defaults)
        #expect(store.linked == nil)
        store.link(try Self.manager())

        // A new store reads the saved link, as after relaunching the app.
        let relaunched = LinkedTeamStore(defaults: defaults)
        #expect(relaunched.linked == LinkedTeam(id: 1, teamName: "Solio Moose", managerName: "Chris Musson"))

        relaunched.unlink()
        #expect(LinkedTeamStore(defaults: defaults).linked == nil)
    }
}

struct TransferTests {

    @Test func decodesTransfersWithFractionalSeconds() throws {
        let json = """
        [{"element_in": 566, "element_out": 114, "event": 9, "time": "2026-10-31T10:08:30.794468Z",
          "element_in_cost": 50, "element_out_cost": 45},
         {"element_in": 40, "element_out": 565, "event": 9, "time": "2026-10-28T23:05:21Z",
          "element_in_cost": null}]
        """
        let transfers = try JSONDecoder.fplAPI.decode([Transfer].self, from: Data(json.utf8))
        #expect(transfers.count == 2)
        #expect(transfers[0].elementIn == 566)
        #expect(transfers[0].elementInCost == 50)
        #expect(transfers[1].elementInCost == nil)
        #expect(transfers[1].elementOutCost == nil)
        #expect(transfers[0].time > transfers[1].time)
    }

    static func transfer(_ elementIn: Int, _ elementOut: Int, day: Int, event: Int = 10) -> Transfer {
        Transfer(elementIn: elementIn, elementOut: elementOut, event: event,
                 time: NoteTests.date(day), elementInCost: 86, elementOutCost: 80)
    }

    static func noteTransfer(_ elementIn: Int, _ elementOut: Int, day: Int) -> NoteTransfer {
        NoteTransfer(playerIn: NotePlayer(id: elementIn, webName: "In\(elementIn)"),
                     playerOut: NotePlayer(id: elementOut, webName: "Out\(elementOut)"),
                     cost: 86, time: NoteTests.date(day))
    }

    @Test func aNoteIsAboutLinkedPlayersAndBothSidesOfItsTransfer() {
        let linked = Note(text: "Watch his minutes", gameweek: 9, players: [NotePlayer(id: 7, webName: "Rogers")])
        let boughtIn = Note(text: "", gameweek: 8, transfer: Self.noteTransfer(7, 2, day: 3))
        let soldOut = Note(text: "Rotation risk", gameweek: 6, transfer: Self.noteTransfer(3, 7, day: 1))
        let mentionedOnly = Note(text: "Rogers looked sharp", gameweek: 9, players: [NotePlayer(id: 4, webName: "Saka")])
        let notes = [linked, boughtIn, soldOut, mentionedOnly]
        #expect(notes.filter { $0.isAbout(7) }.map(\.gameweek) == [9, 8, 6])
        #expect(notes.filter { $0.isAbout(4) }.count == 1)
        #expect(!notes.contains { $0.isAbout(99) })
    }

    @Test func onlyTransfersAfterTheLastCheckAreNewOldestFirst() {
        let transfers = [Self.transfer(3, 4, day: 9), Self.transfer(1, 2, day: 7), Self.transfer(5, 6, day: 3)]
        let new = Transfer.made(after: NoteTests.date(5), in: transfers)
        #expect(new.map(\.elementIn) == [1, 3])
    }

    @Test func profileGroupsTransfersByGameweekLatestFirst() {
        let transfers = [Self.transfer(1, 2, day: 2, event: 9), Self.transfer(3, 4, day: 9, event: 10),
                         Self.transfer(5, 6, day: 4, event: 9)]
            .map { NamedTransfer($0, names: [1: "Isak"]) }
        let groups = NamedTransfer.byGameweek(transfers)
        #expect(groups.map(\.gameweek) == [10, 9])
        #expect(groups[1].transfers.map(\.transfer.elementIn) == [5, 1])
        #expect(groups[1].transfers[1].noteTransfer.playerIn.webName == "Isak")
        #expect(groups[1].transfers[1].noteTransfer.playerOut.webName == "Unknown player")
    }

    static func history(_ transfers: [Int], startingAt first: Int = 1, chips: [(String, Int)] = []) -> ManagerHistory {
        ManagerHistory(
            current: transfers.enumerated().map { GameweekHistory(event: first + $0.offset, eventTransfers: $0.element) },
            chips: chips.map { ChipUsed(name: $0.0, event: $0.1) })
    }

    @Test func freeTransfersMatchManagerOnesSeason() {
        // Manager 1 to GW9: Wildcard in GW3, Free Hit in GW5, 1, 2 and 3 transfers in GW6, 8 and 9, no hits.
        let history = Self.history([0, 0, 0, 0, 0, 1, 0, 2, 3], chips: [("bboost", 2), ("wildcard", 3), ("freehit", 5)])
        #expect(FreeTransfers.available(history: history, upcoming: []) == 1)
    }

    @Test func wildcardAndFreeHitKeepSavedTransfersWithoutAddingOne() {
        // 2 saved going into GW3, Wildcard in GW3, so still 2 for GW4.
        #expect(FreeTransfers.available(history: Self.history([0, 0, 0], chips: [("wildcard", 3)]), upcoming: []) == 2)
        #expect(FreeTransfers.available(history: Self.history([0, 0, 0], chips: [("bboost", 3)]), upcoming: []) == 3)
    }

    @Test func freeTransfersCapAtFiveAndNeverGoBelowZero() {
        #expect(FreeTransfers.available(history: Self.history(Array(repeating: 0, count: 9)), upcoming: []) == 5)
        // A hit in GW2 (3 transfers on 1) leaves 1 for GW3, not -1.
        #expect(FreeTransfers.available(history: Self.history([0, 3]), upcoming: []) == 1)
        // Joining in GW5: unlimited that week, then 1 for GW6.
        #expect(FreeTransfers.available(history: Self.history([15], startingAt: 5), upcoming: []) == 1)
        #expect(FreeTransfers.available(history: Self.history([]), upcoming: []) == nil)
    }

    @Test func transfersForTheNextGameweekUseFreeOnes() {
        let history = Self.history([0, 0, 0])  // 3 free for GW4
        let upcoming = [Self.transfer(1, 2, day: 2, event: 4), Self.transfer(3, 4, day: 1, event: 3)]
        #expect(FreeTransfers.available(history: history, upcoming: upcoming) == 2)
        let wildcard = Self.history([0, 0, 0], chips: [("wildcard", 4)])
        #expect(FreeTransfers.available(history: wildcard, upcoming: upcoming) == 3)
    }

    @Test func transfersKeepTheSellingPriceAndOldNotesStillLoad() throws {
        let named = NamedTransfer(Self.transfer(1, 2, day: 1), names: [:])
        #expect(named.noteTransfer.outCost == 80)
        // Saved before outCost existed.
        let old = #"{"playerIn":{"id":1,"webName":"Isak"},"playerOut":{"id":2,"webName":"Watkins"},"cost":86,"time":0}"#
        let decoded = try JSONDecoder().decode(NoteTransfer.self, from: Data(old.utf8))
        #expect(decoded.cost == 86)
        #expect(decoded.outCost == nil)
    }

    @Test func popoverUsesTheSeasonsTransfersWithTheNoteWhenThereIsOne() throws {
        let history = [Self.transfer(7, 2, day: 1, event: 8), Self.transfer(9, 7, day: 5, event: 11),
                       Self.transfer(3, 4, day: 6, event: 11)]
            .map { NamedTransfer($0, names: [9: "Isak"]) }
        let sale = Note(text: "Injured", gameweek: 11, transfer: history[1].noteTransfer)

        let sold = try #require(Note.latestTransfer(for: 7, history: history, notes: [sale]))
        #expect(!sold.broughtIn)
        #expect(sold.gameweek == 11)
        #expect(sold.transfer.playerIn.webName == "Isak")
        #expect(sold.note?.text == "Injured")

        // Bought before linking: shown, but with no note.
        let bought = try #require(Note.latestTransfer(for: 3, history: history, notes: [sale]))
        #expect(bought.broughtIn)
        #expect(bought.note == nil)

        #expect(Note.latestTransfer(for: 42, history: history, notes: [sale]) == nil)
        // Not loaded yet: falls back to the notes.
        #expect(Note.latestTransfer(for: 7, history: nil, notes: [sale])?.note?.text == "Injured")
    }

    @Test func transfersFindTheirOwnNote() {
        let transfer = Self.transfer(1, 2, day: 3)
        let sameDayOtherPlayer = Self.transfer(5, 6, day: 3)
        let note = Note(text: "Fixtures", gameweek: 10, transfer: NamedTransfer(transfer, names: [:]).noteTransfer)
        let plain = Note(text: "Captain?", gameweek: 10, players: [NotePlayer(id: 1, webName: "In1")])
        #expect(Note.forTransfer(transfer, in: [plain, note]) === note)
        #expect(Note.forTransfer(sameDayOtherPlayer, in: [plain, note]) == nil)
    }

    @Test func gameweekScoreHasPointsHitsAndRankMovement() throws {
        let json = """
        {"current": [
          {"event": 7, "points": 77, "overall_rank": 516849, "event_transfers": 1, "event_transfers_cost": 0},
          {"event": 8, "points": 56, "overall_rank": 337752, "event_transfers": 2, "event_transfers_cost": 4},
          {"event": 9, "points": 37, "overall_rank": 753169, "event_transfers": 1, "event_transfers_cost": null}],
         "chips": [], "past": []}
        """
        let history = try JSONDecoder.fplAPI.decode(ManagerHistory.self, from: Data(json.utf8))

        let first = try #require(history.score(for: 7))
        #expect(first.rankChange == nil)

        let up = try #require(history.score(for: 8))
        #expect(up.points == 56)
        #expect(up.hitCost == 4)
        #expect(up.rankChange == 179_097)
        #expect(up.accessibilityDescription == "56 points, minus 4 for transfers. Overall rank 337,752, up 179,097 places")

        let down = try #require(history.score(for: 9))
        #expect(down.hitCost == 0)
        #expect(down.rankChange == -415_417)

        #expect(history.score(for: 10) == nil)
        #expect(GameweekScore.compact(337_752) == "338K")
        #expect(GameweekScore.compact(7_045_139) == "7.05M")
    }

    @Test func summaryNamesBothPlayersAndThePrice() {
        #expect(Self.noteTransfer(1, 2, day: 1).summary == "In1 in · Out2 out · £8.6m")
    }

    @Test func popoverUsesTheLatestTransferForThePlayer() throws {
        let bought = Note(text: "Great fixtures", gameweek: 8, transfer: Self.noteTransfer(7, 2, day: 1))
        let sold = Note(text: "Injured", gameweek: 11, transfer: Self.noteTransfer(9, 7, day: 5))
        let free = Note(text: "Watch him", gameweek: 9, players: [NotePlayer(id: 7, webName: "In7")])

        let latest = try #require(Note.latestTransferNote(for: 7, in: [bought, sold, free]))
        #expect(latest.note.text == "Injured")
        #expect(!latest.broughtIn)

        let onlyBought = try #require(Note.latestTransferNote(for: 7, in: [bought, free]))
        #expect(onlyBought.broughtIn)

        // Never transferred (a free note alone doesn't count).
        #expect(Note.latestTransferNote(for: 7, in: [free]) == nil)
    }

    @Test func skippedTransferNotesCanStillBeWrittenOnce() {
        let skipped = Note(text: "", gameweek: 8, transfer: Self.noteTransfer(1, 2, day: 1))
        #expect(!skipped.isLocked(currentGameweek: 9))
        skipped.text = "Fixtures"
        #expect(skipped.isLocked(currentGameweek: 9))
    }

    @Test func undoKeepsTheTransfer() {
        let note = Note(text: "Fixtures", gameweek: 10, transfer: Self.noteTransfer(1, 2, day: 1))
        #expect(DeletedNote(note).restored().transfer == note.transfer)
    }

    @MainActor @Test func linkingStartsWatchingFromNow() throws {
        let suite = "FPLTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let before = Date.now
        LinkedTeamStore(defaults: defaults).link(try ManagerTests.manager())
        let seen = try #require(defaults.object(forKey: "transfersSeenUntil") as? Date)
        #expect(seen >= before)

        LinkedTeamStore(defaults: defaults).unlink()
        #expect(defaults.object(forKey: "transfersSeenUntil") == nil)
    }
}

struct PicksTests {
    /// Trimmed from `/api/managers/{id}/picks` for a Triple Captain gameweek
    /// with an automatic sub, plus a pick with nulls.
    static let json = """
    {
      "active_chip": "3xc",
      "picks": [
        {"element": 30, "position": 9, "multiplier": 3, "is_captain": true, "is_vice_captain": false, "element_type": 4},
        {"element": 1, "position": 1, "multiplier": 1, "is_captain": false, "is_vice_captain": false, "element_type": 1},
        {"element": 20, "position": 6, "multiplier": 1, "is_captain": false, "is_vice_captain": true, "element_type": 3},
        {"element": 10, "position": 2, "multiplier": 1, "is_captain": false, "is_vice_captain": false, "element_type": 2},
        {"element": 11, "position": 3, "multiplier": null, "is_captain": null, "is_vice_captain": null, "element_type": null},
        {"element": 2, "position": 12, "multiplier": 0, "is_captain": false, "is_vice_captain": false, "element_type": 1},
        {"element": 12, "position": 13, "multiplier": 1, "is_captain": false, "is_vice_captain": false, "element_type": 2}
      ],
      "automatic_subs": [{"element_in": 12, "element_out": 10, "event": 9}],
      "entry_history": {"event": 9, "points": 55, "total_points": 563, "bank": 21, "value": 1022, "points_on_bench": 13}
    }
    """

    static func picks() throws -> ManagerPicks {
        try JSONDecoder.fplAPI.decode(ManagerPicks.self, from: Data(json.utf8))
    }

    @Test func decodesPicksWithNulls() throws {
        let picks = try Self.picks()
        #expect(picks.picks.count == 7)
        #expect(picks.entryHistory == .init(event: 9, points: 55, pointsOnBench: 13))
        #expect(picks.chipTitle == "Triple Captain")
        let unknown = try #require(picks.picks.first { $0.element == 11 })
        #expect(unknown.multiplier == nil && unknown.badge == nil)
    }

    @Test func onlyElementAndPositionAreRequired() throws {
        let data = Data(#"{"picks": [{"element": 1, "position": 1}]}"#.utf8)
        let picks = try JSONDecoder.fplAPI.decode(ManagerPicks.self, from: data)
        #expect(picks.activeChip == nil && picks.automaticSubs == nil && picks.entryHistory == nil)
        #expect(picks.chipTitle == nil)
    }

    @Test func startersGroupByPositionAndBenchKeepsItsOrder() throws {
        let picks = try Self.picks()
        // Element 11 has no element_type, so the player list fills it in.
        var object = try ElementDecodingTests.fixtureObject()
        object["id"] = 11
        object["element_type"] = 2
        let players = [11: try ElementDecodingTests.decode(object)]
        let lines = picks.startingLines(players: players)
        #expect(lines.map(\.position) == [.goalkeeper, .defender, .midfielder, .forward])
        #expect(lines[1].picks.map(\.element) == [10, 11])
        #expect(picks.bench.map(\.element) == [2, 12])
        #expect(Element.Position.allCases.map(\.shortTitle) == ["GKP", "DEF", "MID", "FWD"])
    }

    @Test func badgesAndAutomaticSubs() throws {
        let picks = try Self.picks()
        let badges = Dictionary(uniqueKeysWithValues: picks.picks.map { ($0.element, $0.badge) })
        #expect(badges[30] == "TC")
        #expect(badges[20] == "V")
        #expect(badges[1] == .some(nil))
        #expect(picks.subbedIn == [12] && picks.subbedOut == [10])
    }

    static func fixture(_ id: Int, event: Int, home: Int, away: Int, started: Bool = false) -> Fixture {
        Fixture(id: id, event: event, teamH: home, teamA: away, teamHDifficulty: 3, teamADifficulty: 3,
                kickoffTime: nil, started: started, finished: false, teamHScore: nil, teamAScore: nil)
    }

    @Test func decodesLivePointsWithNulls() throws {
        let data = Data(#"[{"id": 1, "total_points": 5, "minutes": 90}, {"id": 2, "total_points": null, "minutes": null}]"#.utf8)
        let elements = try JSONDecoder.fplAPI.decode([LiveElement].self, from: data)
        #expect(elements == [LiveElement(id: 1, totalPoints: 5, minutes: 90), LiveElement(id: 2)])
        let live = LivePoints(gameweek: 9, elements: elements, fixtures: nil)
        #expect(live.points == [1: 5] && live.minutes == [1: 90])
    }

    @Test func scoresCountTheMultiplierAndBenchShowsItsOwnPoints() throws {
        let picks = try Self.picks()
        let live = LivePoints(gameweek: 9, elements: [
            LiveElement(id: 30, totalPoints: 8, minutes: 90),   // triple captain
            LiveElement(id: 1, totalPoints: 2, minutes: 90),
            LiveElement(id: 2, totalPoints: 3, minutes: 90),    // bench, multiplier 0
            LiveElement(id: 11, totalPoints: nil, minutes: nil),
        ], fixtures: [])
        func score(_ element: Int) throws -> PickScore? {
            live.score(for: try #require(picks.picks.first { $0.element == element }), team: 5)
        }
        #expect(try score(30) == .points(24))
        #expect(try score(1) == .points(2))
        #expect(try score(2) == .points(3))
        // Null points are unknown, not 0.
        #expect(try score(11) == nil)
    }

    @Test func playersWhoseMatchHasntStartedAreYetToPlay() throws {
        let pick = ManagerPicks.Pick(element: 1, position: 1, multiplier: 1)
        let fixtures = [Self.fixture(1, event: 9, home: 5, away: 6), Self.fixture(2, event: 10, home: 7, away: 8)]
        let notStarted = LivePoints(gameweek: 9, elements: [LiveElement(id: 1, totalPoints: 0, minutes: 0)], fixtures: fixtures)
        #expect(notStarted.score(for: pick, team: 6) == .yetToPlay)
        // His team's only match next gameweek doesn't count.
        #expect(notStarted.score(for: pick, team: 7) == .points(0))
        // A double where he's played the first match: points so far.
        let doubleHalfPlayed = LivePoints(gameweek: 9, elements: [LiveElement(id: 1, totalPoints: 6, minutes: 90)], fixtures: fixtures)
        #expect(doubleHalfPlayed.score(for: pick, team: 5) == .points(6))
        // Before the gameweek the live list is empty.
        let beforeKickoff = LivePoints(gameweek: 9, elements: [], fixtures: fixtures)
        #expect(beforeKickoff.score(for: pick, team: 5) == .yetToPlay)
        // Without fixtures nobody is marked yet to play.
        let noFixtures = LivePoints(gameweek: 9, elements: [LiveElement(id: 1, totalPoints: 0, minutes: 0)], fixtures: nil)
        #expect(noFixtures.score(for: pick, team: 6) == .points(0))
    }

    @Test func squadStateKeepsASquadOnScreenWhenARefreshFails() throws {
        let picks = try Self.picks()
        let down: Result<ManagerPicks, Error> = .failure(FPLAPIClient.APIError.dataUnavailable("FPL is unavailable right now"))
        let missing: Result<ManagerPicks, Error> = .failure(FPLAPIClient.APIError.notFound("Manager not found"))

        #expect(SquadState(.success(picks), playersLoaded: true, previous: .loading) == .loaded(picks))
        #expect(SquadState(.success(picks), playersLoaded: false, previous: .loading) == .failed)
        #expect(SquadState(down, playersLoaded: true, previous: .loading) == .failed)
        #expect(SquadState(down, playersLoaded: true, previous: .loaded(picks)) == .loaded(picks))
        #expect(SquadState(missing, playersLoaded: true, previous: .loaded(picks)) == .none)
    }
}

/// Answers requests from `StubURLProtocol.responses` by path, after `delay`, so
/// a test can cancel a load while its requests are still in flight. Used only
/// through `session`, never registered globally.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (status: Int, body: String)] = [:]
    nonisolated(unsafe) static var delay: TimeInterval = 0

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// Set by `stopLoading` on URLSession's thread, read on the delayed response's.
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) { [self] in
            guard !stopped.withLock({ $0 }), let url = request.url else { return }
            let stub = Self.responses[url.path] ?? (404, #"{"detail": "Not found"}"#)
            let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() { stopped.withLock { $0 = true } }
}

struct KitColorTests {
    @Test func teamsDecodeColorsAsOptional() throws {
        let data = Data(#"""
        [{"id": 1, "code": 3, "name": "Arsenal", "short_name": "ARS", "primary_color": "#EF0107", "secondary_color": "#FFFFFF"},
         {"id": 21, "name": "Promoted", "short_name": "PRO", "primary_color": null, "secondary_color": null},
         {"id": 22, "name": "Older API", "short_name": "OLD"}]
        """#.utf8)
        let teams = try JSONDecoder.fplAPI.decode([Team].self, from: data)
        #expect(teams[0].primaryColor == "#EF0107" && teams[0].secondaryColor == "#FFFFFF")
        #expect(teams[1].primaryColor == nil && teams[1].secondaryColor == nil)
        #expect(teams[2].primaryColor == nil)
    }

    @Test func hexStringsParseOrGiveNil() {
        #expect(UInt32(hexValue: "#EF0107") == 0xEF0107)
        #expect(UInt32(hexValue: "ef0107") == 0xEF0107)
        #expect(UInt32(hexValue: "#FFF") == nil)
        #expect(UInt32(hexValue: "#GG0000") == nil)
        #expect(UInt32(hexValue: "") == nil)
        #expect(UInt32(hexValue: nil) == nil)
    }

    @Test func onlyDarkKitsGetAHairline() {
        let kit = { (hex: String) in KitColors(primary: hex, secondary: "#FFFFFF") }
        // Newcastle black, Everton navy.
        #expect(kit("#000000").needsHairline)
        #expect(kit("#003399").needsHairline)
        // White and bright kits.
        #expect(!kit("#FFFFFF").needsHairline)
        #expect(!kit("#6CABDD").needsHairline)
        #expect(!kit("#F5A12D").needsHairline)
    }

    @Test func goalkeepersAndUnknownClubsGetFixedColors() {
        #expect(KitColors.goalkeeper.primary == Theme.goalkeeperShirtHex)
        // Pink needs no hairline.
        #expect(!KitColors.goalkeeper.needsHairline)
        let unknown = KitColors(primary: nil, secondary: "#FFFFFF")
        #expect(unknown.primary == Theme.shirtHex && unknown.secondary == nil)
        let badHex = KitColors(primary: "red", secondary: nil)
        #expect(badHex.primary == Theme.shirtHex)
    }
}

struct TransferNetTests {
    static let rows = #"""
    [{"element_in": 566, "element_out": 114, "event": 9, "time": "2026-10-31T10:08:30.794468Z",
      "element_in_cost": 50, "element_out_cost": 45, "is_churn": false, "points_in": 8, "points_out": 6, "net_points": 2},
     {"element_in": 7, "element_out": 8, "event": 3, "time": "2026-09-12T09:00:00.000000Z",
      "element_in_cost": 60, "element_out_cost": 61, "is_churn": true, "points_in": null, "points_out": null, "net_points": null},
     {"element_in": 9, "element_out": 10, "event": 3, "time": "2026-09-11T09:00:00.000000Z",
      "element_in_cost": 55, "element_out_cost": 52, "is_churn": false, "points_in": 3, "points_out": 9, "net_points": -6}]
    """#

    func transfer(event: Int, net: Int?) -> Transfer {
        var transfer = TransferTests.transfer(1, 2, day: 1, event: event)
        transfer.netPoints = net
        return transfer
    }

    @Test func decodesNetPointsAndOlderResponses() throws {
        let transfers = try JSONDecoder.fplAPI.decode([Transfer].self, from: Data(Self.rows.utf8))
        #expect(transfers[0].netPoints == 2 && transfers[0].pointsIn == 8 && transfers[0].isChurn == false)
        #expect(transfers[1].isChurn == true && transfers[1].netPoints == nil)
        // Before FPL-33 the API sent none of these fields.
        let old = try JSONDecoder.fplAPI.decode(Transfer.self, from: Data(#"""
        {"element_in": 1, "element_out": 2, "event": 3, "time": "2026-09-11T09:00:00.000000Z",
         "element_in_cost": 50, "element_out_cost": 45}
        """#.utf8))
        #expect(old.isChurn == nil && old.netPoints == nil)
    }

    @Test func netSubtractsHitsAndSkipsUnknownPoints() {
        let history = ManagerHistory(current: [
            GameweekHistory(event: 3, eventTransfers: 2, eventTransfersCost: 4),
            GameweekHistory(event: 9, eventTransfers: 1),
        ], chips: [])
        let transfers = [transfer(event: 9, net: 2), transfer(event: 10, net: nil), transfer(event: 3, net: -6)]
        #expect(Transfer.net(of: transfers, history: history) == -8)
        // Nothing to show while no transfer has points, or without hits to subtract.
        #expect(Transfer.net(of: [transfer(event: 10, net: nil)], history: history) == nil)
        #expect(Transfer.net(of: transfers, history: nil) == nil)
    }

    @Test func pointsReadWithSignAndForVoiceOver() {
        #expect(PointsLabel.text(2) == "+2 pts")
        #expect(PointsLabel.text(-5) == "\u{2212}5 pts")
        #expect(PointsLabel.text(0) == "0 pts")
        #expect(PointsLabel.description(1) == "gained 1 point")
        #expect(PointsLabel.description(-1) == "lost 1 point")
        #expect(PointsLabel.description(-5) == "lost 5 points")
        #expect(PointsLabel.description(0) == "no change in points")
    }

    @Test func notesMatchOnGameweekAndPlayersNotTime() {
        let saved = TransferTests.noteTransfer(9, 10, day: 1)
        let note = Note(text: "Fixtures", gameweek: 3, transfer: saved)
        // A row the API built for a chip week can carry a different time.
        var built = TransferTests.transfer(9, 10, day: 5, event: 3)
        #expect(Note.forTransfer(built, in: [note]) === note)
        built = TransferTests.transfer(9, 10, day: 1, event: 4)
        #expect(Note.forTransfer(built, in: [note]) == nil)
        #expect(Note.forTransfer(TransferTests.transfer(9, 11, day: 1, event: 3), in: [note]) == nil)
    }

    @Test func aRepeatedSwapKeepsDistinctIDs() {
        // Unmarked churn can list the same swap twice in one gameweek.
        let first = NamedTransfer(TransferTests.transfer(9, 10, day: 1, event: 3), names: [:])
        let again = NamedTransfer(TransferTests.transfer(9, 10, day: 2, event: 3), names: [:])
        #expect(first.id != again.id)
    }

    @Test func moreThanASquadOfTransfersInAGameweekIsUnmarkedChurn() {
        let wildcard = (1...15).map { TransferTests.transfer($0, $0 + 100, day: 1, event: 3) }
        #expect(!Transfer.hasUnmarkedChurn(wildcard))
        #expect(Transfer.hasUnmarkedChurn(wildcard + [TransferTests.transfer(50, 51, day: 1, event: 3)]))
        // Counted per gameweek.
        #expect(!Transfer.hasUnmarkedChurn(wildcard + [TransferTests.transfer(50, 51, day: 1, event: 4)]))
    }

    @Test func popoverGetsTheLatestTransfersNet() {
        var bought = TransferTests.transfer(9, 10, day: 5, event: 9)
        bought.netPoints = 2
        let history = [NamedTransfer(bought, names: [9: "Isak", 10: "Watkins"])]
        #expect(Note.latestTransfer(for: 9, history: history, notes: [])?.netPoints == 2)
    }
}

/// Suites that share `StubURLProtocol`'s static responses, run one at a time.
@Suite(.serialized)
struct StubbedNetworkTests {}

extension StubbedNetworkTests {
    @MainActor @Suite
    struct EarlierSquadTests {
        /// A linked store on its own UserDefaults suite; call `cleanup` when done.
        func store() throws -> (store: LinkedTeamStore, cleanup: () -> Void) {
            let suite = "FPLTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            let client = FPLAPIClient(baseURL: URL(string: "https://stub.test/api")!, session: StubURLProtocol.session)
            let store = LinkedTeamStore(defaults: defaults, client: client)
            store.link(try ManagerTests.manager())
            return (store, { defaults.removePersistentDomain(forName: suite) })
        }

        func stubSquad(managerID: Int) {
            StubURLProtocol.responses = [
                "/api/managers/\(managerID)/picks": (200, PicksTests.json),
                "/api/events/8/live": (200, #"[{"id": 30, "total_points": 8, "minutes": 90}]"#),
                "/api/elements": (200, "[]"),
            ]
        }

        @Test func aCancelledLoadDoesNotShowRetry() async throws {
            let (store, cleanup) = try store()
            defer { cleanup() }
            stubSquad(managerID: try #require(store.linked?.id))
            StubURLProtocol.delay = 0.5

            // Stepping past gameweek 8 before it loads cancels its task.
            let load = Task { await store.loadSquad(gameweek: 8) }
            try await Task.sleep(for: .milliseconds(50))
            load.cancel()
            await load.value
            #expect(store.earlierSquads[8] == .loading)
            #expect(store.earlierPoints[8] == nil)

            // Coming back to it loads it.
            StubURLProtocol.delay = 0
            await store.loadSquad(gameweek: 8)
            #expect(store.earlierSquads[8] == .loaded(try PicksTests.picks()))
            #expect(store.earlierPoints[8]?.points == [30: 8])
        }

        @Test func aFailedLoadShowsRetryAndA404ShowsNoSquad() async throws {
            let (store, cleanup) = try store()
            defer { cleanup() }
            let id = try #require(store.linked?.id)
            StubURLProtocol.delay = 0

            StubURLProtocol.responses = ["/api/managers/\(id)/picks": (503, #"{"detail": "FPL is unavailable right now"}"#)]
            await store.loadSquad(gameweek: 8)
            #expect(store.earlierSquads[8] == .failed)

            StubURLProtocol.responses = [:]
            await store.loadSquad(gameweek: 2)
            #expect(store.earlierSquads[2] == SquadState.none)
        }
    }

    @MainActor
    struct TransferChurnTests {
        /// A linked store whose transfers since linking are `rows` (all in GW10).
        func store(rows: [String]) throws -> (store: LinkedTeamStore, cleanup: () -> Void) {
            let suite = "FPLTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            let client = FPLAPIClient(baseURL: URL(string: "https://stub.test/api")!, session: StubURLProtocol.session)
            let store = LinkedTeamStore(defaults: defaults, client: client)
            let manager = try ManagerTests.manager()
            store.link(manager)
            StubURLProtocol.delay = 0
            StubURLProtocol.responses = [
                "/api/managers/\(manager.id)/transfers": (200, "[" + rows.joined(separator: ",") + "]"),
                "/api/managers/\(manager.id)/history": (200, #"""
                {"current": [{"event": 9, "points": 50, "overall_rank": 1000,
                              "event_transfers": 1, "event_transfers_cost": 4}],
                 "chips": []}
                """#),
                "/api/elements": (200, "[]"),
            ]
            return (store, { defaults.removePersistentDomain(forName: suite) })
        }

        /// A transfer made after linking, for GW10.
        func row(_ elementIn: Int, net: Int? = nil) -> String {
            let net = net.map(String.init) ?? "null"
            return #"{"element_in": \#(elementIn), "element_out": \#(elementIn + 100), "event": 10, "#
                + #""time": "2099-01-01T10:00:00.000000Z", "element_in_cost": 50, "element_out_cost": 45, "#
                + #""is_churn": false, "net_points": \#(net)}"#
        }

        @Test func thePromptWaitsWhenChurnIsUnmarked() async throws {
            let (store, cleanup) = try store(rows: (1...20).map { row($0) })
            defer { cleanup() }
            await store.checkForTransfers()
            #expect(store.pendingTransfers.isEmpty)
        }

        @Test func realTransfersArePrompted() async throws {
            let (store, cleanup) = try store(rows: [row(1), row(2)])
            defer { cleanup() }
            await store.checkForTransfers()
            #expect(store.pendingTransfers.count == 2)
        }

        @Test func transferNetSubtractsHitsAfterARefresh() async throws {
            let (store, cleanup) = try store(rows: [row(1, net: 6), row(2)])
            defer { cleanup() }
            await store.refresh()
            #expect(store.transferNet == 2)
        }

        @Test func theClientDropsChurn() async throws {
            StubURLProtocol.delay = 0
            StubURLProtocol.responses = ["/api/managers/1/transfers": (200, TransferNetTests.rows)]
            let client = FPLAPIClient(baseURL: URL(string: "https://stub.test/api")!, session: StubURLProtocol.session)
            let transfers = try await client.transfers(managerID: 1)
            #expect(transfers.map(\.elementIn) == [566, 9])
        }
    }
}

struct LoggingTests {
    @Test func routeHidesTheManagerID() {
        #expect(FPLAPIClient.route("managers/3039435/transfers") == "managers/{id}/transfers")
        #expect(FPLAPIClient.route("managers/1") == "managers/{id}")
        #expect(FPLAPIClient.route("events/9/live") == "events/9/live")
    }

    @Test func decodingSummaryNamesTheKeyAndPath() throws {
        var object = try ElementDecodingTests.fixtureObject()
        object.removeValue(forKey: "web_name")
        let data = try JSONSerialization.data(withJSONObject: [object])
        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder.fplAPI.decode([Element].self, from: data)
        }
        #expect(error.logSummary == "missing key webName at [0]")
    }

    @Test func decodingSummaryForAWrongType() throws {
        var object = try ElementDecodingTests.fixtureObject()
        object["now_cost"] = "62"
        let error = try #require(throws: DecodingError.self) {
            try ElementDecodingTests.decode(object)
        }
        #expect(error.logSummary.hasPrefix("expected Int at nowCost"))
    }

    @Test func otherErrorsLogDomainAndCode() {
        #expect(URLError(.notConnectedToInternet).logSummary == "NSURLErrorDomain -1009")
    }
}
