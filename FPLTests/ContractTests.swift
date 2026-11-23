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

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder.fplAPI.decode(T.self, from: fixture(name))
    }

    @Test func elements() throws {
        let elements = try Self.decode([Element].self, from: "elements")
        #expect(!elements.isEmpty)
        #expect(Set(elements.compactMap(\.position)).count == 4)
    }

    @Test func element() throws {
        #expect(try Self.decode(Element.self, from: "element").id == 1)
    }

    @Test func elementsByPosition() throws {
        let goalkeepers = try Self.decode([Element].self, from: "elements-position")
        #expect(!goalkeepers.isEmpty)
        #expect(goalkeepers.allSatisfy { $0.position == .goalkeeper })
    }

    @Test func teams() throws {
        #expect(try Self.decode([Team].self, from: "teams").count == 20)
    }

    @Test func upcomingFixtures() throws {
        _ = try Self.decode([Fixture].self, from: "fixtures")
    }

    @Test func gameweekFixtures() throws {
        let fixtures = try Self.decode([Fixture].self, from: "event-fixtures")
        // Only this endpoint sends them, and the Gameweek tab needs both.
        #expect(fixtures.allSatisfy { $0.minutes != nil && $0.finishedProvisional != nil })
    }

    @Test func events() throws {
        let events = try Self.decode([Event].self, from: "events")
        #expect(events.count == 38)
    }

    @Test func livePoints() throws {
        _ = try Self.decode([LiveElement].self, from: "live")
    }

    @Test func manager() throws {
        let manager = try Self.decode(Manager.self, from: "manager")
        #expect(manager.id == 1)
        let leagues = try #require(manager.leagues)
        #expect(leagues.contains { $0.id == 314 && $0.kind == .system })
        #expect(!leagues.contains { $0.kind == .unknown })
    }

    @Test func league() throws {
        let league = try Self.decode(LeagueStandings.self, from: "league")
        #expect(league.id == 314)
        #expect(league.standings.count == 50)
        #expect(league.hasNext)
    }

    @Test func transfers() throws {
        _ = try Self.decode([Transfer].self, from: "transfers")
    }

    @Test func history() throws {
        _ = try Self.decode(ManagerHistory.self, from: "history")
    }

    @Test func picks() throws {
        #expect(try Self.decode(ManagerPicks.self, from: "picks").picks.count == 15)
    }
}
