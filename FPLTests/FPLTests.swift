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

struct ElementFilterTests {

    static func element(price: Int, points: Int?, goals: Int?, assists: Int?) throws -> Element {
        var object = try ElementDecodingTests.fixtureObject()
        object["now_cost"] = price
        object["total_points"] = points ?? NSNull()
        object["goals_scored"] = goals ?? NSNull()
        object["assists"] = assists ?? NSNull()
        return try ElementDecodingTests.decode(object)
    }

    @Test func defaultFilterMatchesEverythingAndIsInactive() throws {
        let filter = ElementFilter()
        #expect(!filter.isActive)
        #expect(filter.matches(try Self.element(price: 45, points: nil, goals: nil, assists: nil)))
    }

    @Test func maxPriceIsInclusive() throws {
        let filter = ElementFilter(maxPrice: 7.5)
        #expect(filter.isActive)
        #expect(filter.matches(try Self.element(price: 75, points: 0, goals: 0, assists: 0)))
        #expect(!filter.matches(try Self.element(price: 76, points: 0, goals: 0, assists: 0)))
    }
}
