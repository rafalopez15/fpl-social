//
//  ProfileRefreshTests.swift
//  FPLTests
//

import Foundation
import Testing
@testable import FPL

/// Profile's pull to refresh, against stubbed fplAPI responses.
extension StubbedNetworkTests {
    @MainActor @Suite
    struct ProfileRefreshTests {
        let client = FPLAPIClient(baseURL: URL(string: "https://stub.test/api")!, session: StubURLProtocol.session)

        static let events = #"""
        [{"id": 9, "name": "Gameweek 9", "deadline_time": "2026-10-31T11:00:00Z", "finished": false,
          "is_current": true, "is_next": false},
         {"id": 10, "name": "Gameweek 10", "deadline_time": "2026-11-07T11:00:00Z", "finished": false,
          "is_current": false, "is_next": true}]
        """#
        /// After gameweek 10's deadline.
        static let laterEvents = events.replacingOccurrences(of: #""is_current": true, "is_next": false"#,
                                                              with: #""is_current": false, "is_next": false"#)
            .replacingOccurrences(of: #""is_current": false, "is_next": true"#, with: #""is_current": true, "is_next": false"#)

        /// A linked store (manager 1) on its own UserDefaults suite; call `cleanup` when done.
        func store() throws -> (store: LinkedTeamStore, cleanup: () -> Void) {
            let suite = "FPLTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            let store = LinkedTeamStore(defaults: defaults, client: client)
            store.link(try ManagerTests.manager())
            return (store, { defaults.removePersistentDomain(forName: suite) })
        }

        func stubAll(picks: String = PicksTests.json) {
            StubURLProtocol.delay = 0
            StubURLProtocol.responses = [
                "/api/managers/1": (200, ManagerTests.response),
                "/api/managers/1/transfers": (200, "[]"),
                "/api/managers/1/history": (200, #"{"current": [], "chips": []}"#),
                "/api/managers/1/picks": (200, picks),
                "/api/events/9/live": (200, "[]"),
                "/api/events/8/live": (200, "[]"),
                "/api/fixtures": (200, "[]"),
                "/api/elements": (200, "[]"),
                "/api/events": (200, Self.events),
            ]
        }

        @Test func aPullThatWorksShowsNoToast() async throws {
            let (store, cleanup) = try store()
            defer { cleanup() }
            stubAll()
            let toast = await ProfileRefresh.pull(gameweeks: GameweekStore(client: client), team: store, viewing: nil)
            #expect(toast == nil)
            #expect(store.manager?.name == "Solio Moose")
            #expect(store.squad == .loaded(try PicksTests.picks()))
        }

        @Test func aFailedPullKeepsWhatsShownAndShowsTheToast() async throws {
            let (store, cleanup) = try store()
            defer { cleanup() }
            stubAll()
            #expect(await store.refresh())
            let manager = store.manager

            StubURLProtocol.responses["/api/managers/1"] = (503, #"{"detail": "FPL is unavailable right now"}"#)
            let toast = await ProfileRefresh.pull(gameweeks: GameweekStore(client: client), team: store, viewing: nil)

            #expect(toast?.message == "Refresh failed. Try again later.")
            #expect(store.manager == manager)
            #expect(store.squad == .loaded(try PicksTests.picks()))
        }

        @Test func aRefreshReportsAFailureWithoutShowingAnything() async throws {
            // Returning to the app calls refresh() directly, which has no toast; only a pull makes one.
            let (store, cleanup) = try store()
            defer { cleanup() }
            stubAll()
            StubURLProtocol.responses["/api/managers/1/picks"] = (503, #"{"detail": "FPL is unavailable right now"}"#)
            #expect(await !store.refresh())
        }

        @Test func aSquadThatIsntOutYetIsntAFailure() async throws {
            let (store, cleanup) = try store()
            defer { cleanup() }
            stubAll()
            StubURLProtocol.responses["/api/managers/1/picks"] = nil
            #expect(await store.refresh())
            #expect(store.squad == SquadState.none)
        }

        @Test func aPullReloadsTheEarlierGameweekBeingViewed() async throws {
            let (store, cleanup) = try store()
            defer { cleanup() }
            stubAll()
            await store.refresh()
            await store.loadSquad(gameweek: 8)
            #expect(store.earlierSquads[8] == .loaded(try PicksTests.picks()))

            let changed = PicksTests.json.replacingOccurrences(of: #""active_chip": "3xc""#, with: #""active_chip": null"#)
            stubAll(picks: changed)
            // Already loaded, so stepping back to it doesn't reload it...
            await store.loadSquad(gameweek: 8)
            #expect(store.earlierSquads[8] == .loaded(try PicksTests.picks()))
            // ...but pulling while viewing it does.
            #expect(await ProfileRefresh.pull(gameweeks: GameweekStore(client: client), team: store, viewing: 8) == nil)
            let reloaded = try JSONDecoder.fplAPI.decode(ManagerPicks.self, from: Data(changed.utf8))
            #expect(store.earlierSquads[8] == .loaded(reloaded))
        }

        @Test func theLatestGameweekIsntAnEarlierOne() async throws {
            let (store, cleanup) = try store()
            defer { cleanup() }
            stubAll()
            await store.refresh()
            #expect(store.earlierGameweek(9) == nil)
            #expect(store.earlierGameweek(8) == 8)
            #expect(store.earlierGameweek(nil) == nil)
        }

        @Test func gameweeksReloadEvenAfterTheyLoaded() async {
            let gameweeks = GameweekStore(client: client)
            stubAll()
            await gameweeks.loadIfNeeded()
            #expect(gameweeks.current == 9)

            StubURLProtocol.responses["/api/events"] = (200, Self.laterEvents)
            await gameweeks.loadIfNeeded()
            #expect(gameweeks.current == 9)
            #expect(await gameweeks.reload())
            #expect(gameweeks.current == 10)

            // A failure keeps them.
            StubURLProtocol.responses["/api/events"] = (503, #"{"detail": "FPL is unavailable right now"}"#)
            #expect(await !gameweeks.reload())
            #expect(gameweeks.current == 10)
            #expect(!gameweeks.didFail)
        }

        @Test func noLinkedTeamStillReloadsTheGameweeks() async throws {
            let suite = "FPLTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            stubAll()
            let gameweeks = GameweekStore(client: client)
            let toast = await ProfileRefresh.pull(gameweeks: gameweeks, team: LinkedTeamStore(defaults: defaults, client: client),
                                                  viewing: nil)
            #expect(toast == nil)
            #expect(gameweeks.current == 9)
        }
    }
}
