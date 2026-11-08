//
//  RequestCountTests.swift
//  FPLTests
//

import Foundation
import Testing
@testable import FPL

/// How many requests reach the network when several parts of the app want the
/// same data at once, as at launch.
extension StubbedNetworkTests {
    @MainActor @Suite
    struct RequestCountTests {
        let client = FPLAPIClient(baseURL: URL(string: "https://stub.test/api")!, session: StubURLProtocol.session)

        init() {
            ProfileRefreshTests().stubAll()
            StubURLProtocol.responses["/api/teams"] = (200, "[]")
            // Long enough for the calls below to overlap.
            StubURLProtocol.delay = 0.2
            StubURLProtocol.resetRequests()
        }

        func linkedStore() throws -> (store: LinkedTeamStore, cleanup: () -> Void) {
            let suite = "FPLTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            let store = LinkedTeamStore(defaults: defaults, client: client)
            store.link(try ManagerTests.manager())
            return (store, { defaults.removePersistentDomain(forName: suite) })
        }

        @Test func identicalRequestsInFlightShareOne() async throws {
            async let first = client.teams()
            async let second = client.teams()
            _ = try await (first, second)
            #expect(StubURLProtocol.requests["/api/teams"] == 1)

            // One made after the first finished goes out again.
            _ = try await client.teams()
            #expect(StubURLProtocol.requests["/api/teams"] == 2)
        }

        @Test func accountRequestsAreNeverShared() async throws {
            StubURLProtocol.responses["/api/me/teams"] = (200, "[]")
            async let first = client.myTeams(accessToken: "abc")
            async let second = client.myTeams(accessToken: "abc")
            _ = try await (first, second)
            #expect(StubURLProtocol.requests["/api/me/teams"] == 2)
        }

        @Test func overlappingRefreshesOfOneTeamMakeOne() async throws {
            let (store, cleanup) = try linkedStore()
            defer { cleanup() }
            async let first = store.refresh()
            async let second = store.refresh()
            _ = await (first, second)
            #expect(StubURLProtocol.requests["/api/managers/1"] == 1)
            #expect(StubURLProtocol.requests["/api/managers/1/picks"] == 1)
        }

        @Test func aRefreshForAnotherTeamDoesntWaitForTheOldOne() async throws {
            let (store, cleanup) = try linkedStore()
            defer { cleanup() }
            StubURLProtocol.responses["/api/managers/2"] = (200, ManagerTests.response.replacingOccurrences(
                of: #""id": 1, "name": "Solio Moose""#, with: #""id": 2, "name": "Team Two""#))
            let first = Task { await store.refresh() }
            try await Task.sleep(for: .milliseconds(50))
            store.link(try JSONDecoder.fplAPI.decode(Manager.self, from: Data(#"{"id": 2, "name": "Team Two"}"#.utf8)))
            await store.refresh()
            _ = await first.value
            #expect(StubURLProtocol.requests["/api/managers/2"] == 1)
            #expect(store.manager?.name == "Team Two")
        }

        @Test func theTransferCheckAndARefreshFetchTransfersOnce() async throws {
            let (store, cleanup) = try linkedStore()
            defer { cleanup() }
            await store.checkForTransfers()
            await store.refresh()
            #expect(StubURLProtocol.requests["/api/managers/1/transfers"] == 1)
        }

        @Test func gameweeksLoadOnceForEveryoneAsking() async {
            let gameweeks = GameweekStore(client: client)
            let lookups = TeamsAndFixturesStore(client: client, gameweeks: gameweeks)
            async let launch: Void = gameweeks.loadIfNeeded()
            async let pull = gameweeks.reload()
            async let schedule: Void = lookups.loadIfNeeded()
            _ = await (launch, pull, schedule)
            #expect(StubURLProtocol.requests["/api/events"] == 1)
            #expect(gameweeks.current == 9)
        }

        @Test func launchAsksForEachListOnce() async throws {
            // What launch starts at once: the gameweeks, Profile's refresh, the transfer
            // check, the shared teams and fixtures, and the Players tab.
            StubURLProtocol.responses["/api/elements/position/4"] = (200, "[]")
            let gameweeks = GameweekStore(client: client)
            let lookups = TeamsAndFixturesStore(client: client, gameweeks: gameweeks)
            let suite = "FPLTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = LinkedTeamStore(defaults: defaults, client: client, lookups: lookups)
            store.link(try ManagerTests.manager())
            let players = ElementViewModel(position: .forward, client: client, lookups: lookups)
            async let gameweeksLoaded: Void = gameweeks.loadIfNeeded()
            async let refreshed = store.refresh()
            async let checked: Void = store.checkForTransfers()
            async let lookupsLoaded: Void = lookups.loadIfNeeded()
            async let playersLoaded: Void = players.fetchElements()
            _ = await (gameweeksLoaded, refreshed, checked, lookupsLoaded, playersLoaded)

            for (path, count) in StubURLProtocol.requests {
                #expect(count == 1, "\(path) was requested \(count) times")
            }
        }
    }
}
