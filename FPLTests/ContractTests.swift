//
//  ContractTests.swift
//  FPLTests
//

import Foundation
import Testing
@testable import FPL

/// Decodes a saved fplAPI response for every endpoint the app uses, so a backend
/// change the models can't read fails here. The fixtures come from
/// `.github/scripts/fetch_contract_fixtures.sh`; the daily contract workflow
/// fetches them from production first.
struct ContractTests {
    private final class BundleToken {}

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json"),
                               "Missing fixture \(name).json")
        return try Data(contentsOf: url)
    }

    /// Decodes an array response and checks that no item was dropped.
    static func decodeArray<T: Decodable>(_ type: T.Type, from name: String) throws -> [T] {
        let data = try fixture(name)
        let decoded = try JSONDecoder.fplAPI.decode([T].self, from: data)
        let raw = try #require(JSONSerialization.jsonObject(with: data) as? [Any])
        #expect(decoded.count == raw.count)
        return decoded
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder.fplAPI.decode(T.self, from: fixture(name))
    }

    @Test func elements() throws {
        let elements = try Self.decodeArray(Element.self, from: "elements")
        #expect(!elements.isEmpty)
        #expect(Set(elements.compactMap(\.position)).count == 4)
    }

    @Test func element() throws {
        #expect(try Self.decode(Element.self, from: "element").id == 1)
    }

    @Test func elementsByPosition() throws {
        let goalkeepers = try Self.decodeArray(Element.self, from: "elements-position")
        #expect(!goalkeepers.isEmpty)
        #expect(goalkeepers.allSatisfy { $0.position == .goalkeeper })
    }

    @Test func teams() throws {
        #expect(try Self.decodeArray(Team.self, from: "teams").count == 20)
    }

    @Test func upcomingFixtures() throws {
        _ = try Self.decodeArray(Fixture.self, from: "fixtures")
    }

    @Test func events() throws {
        let events = try Self.decodeArray(Event.self, from: "events")
        #expect(events.count == 38)
    }

    @Test func livePoints() throws {
        _ = try Self.decodeArray(LiveElement.self, from: "live")
    }

    @Test func manager() throws {
        #expect(try Self.decode(Manager.self, from: "manager").id == 1)
    }

    @Test func transfers() throws {
        _ = try Self.decodeArray(Transfer.self, from: "transfers")
    }

    @Test func history() throws {
        _ = try Self.decode(ManagerHistory.self, from: "history")
    }

    @Test func picks() throws {
        #expect(try Self.decode(ManagerPicks.self, from: "picks").picks.count == 15)
    }
}
