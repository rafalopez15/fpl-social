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
