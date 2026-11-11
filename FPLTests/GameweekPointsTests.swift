//
//  GameweekPointsTests.swift
//  FPLTests
//

import Foundation
import Testing
@testable import FPL

/// A live gameweek's points: the sum the squad's cards add up to, and when FPL's
/// own numbers take over.
struct GameweekPointsTests {
    /// Each player's own points in gameweek 9.
    static let live = LivePoints(gameweek: 9, elements: [
        LiveElement(id: 1, totalPoints: 6, minutes: 90),
        LiveElement(id: 2, totalPoints: 2, minutes: 90),
        LiveElement(id: 3, totalPoints: 10, minutes: 90),
        LiveElement(id: 4, totalPoints: 3, minutes: 90),
        LiveElement(id: 5, totalPoints: 1, minutes: 90),
    ], fixtures: nil)

    /// Picks 1–3 start and 4–5 are on the bench, with these multipliers. FPL's own
    /// numbers are behind: 20 points, 1 on the bench.
    static func picks(multipliers: [Int?] = [1, 1, 2, 0, 0], gameweek: Int? = 9) -> ManagerPicks {
        let picks = multipliers.enumerated().map { index, multiplier in
            ManagerPicks.Pick(element: index + 1, position: index < 3 ? index + 1 : index + 9, multiplier: multiplier)
        }
        return ManagerPicks(picks: picks, entryHistory: .init(event: gameweek, points: 20, pointsOnBench: 1))
    }

    static func event(_ id: Int = 9, finished: Bool = false, dataChecked: Bool? = false) -> Event {
        Event(id: id, name: "Gameweek \(id)", deadlineTime: .now, finished: finished,
              isCurrent: true, isNext: false, dataChecked: dataChecked)
    }

    @Test func theCaptainCountsDouble() {
        let points = Self.picks().gameweekPoints(live: Self.live, event: Self.event())
        #expect(points == GameweekPoints(gameweek: 9, points: 6 + 2 + 10 * 2, bench: 3 + 1, isLive: true))
    }

    @Test func aTripleCaptainCountsTriple() {
        let points = Self.picks(multipliers: [1, 1, 3, 0, 0]).gameweekPoints(live: Self.live, event: Self.event())
        #expect(points?.points == 6 + 2 + 10 * 3)
        #expect(points?.bench == 4)
    }

    @Test func benchBoostCountsTheBench() {
        let points = Self.picks(multipliers: [1, 1, 2, 1, 1]).gameweekPoints(live: Self.live, event: Self.event())
        #expect(points?.points == 6 + 2 + 10 * 2 + 3 + 1)
        #expect(points?.bench == 0)
    }

    @Test func playersYetToPlayCountZero() {
        // Player 3, the captain, has no live row yet, and player 2 hasn't kicked off.
        let live = LivePoints(gameweek: 9, elements: [
            LiveElement(id: 1, totalPoints: 6, minutes: 90),
            LiveElement(id: 2, totalPoints: 0, minutes: 0),
            LiveElement(id: 4, totalPoints: 3, minutes: 90),
        ], fixtures: nil)
        let points = Self.picks().gameweekPoints(live: live, event: Self.event())
        #expect(points == GameweekPoints(gameweek: 9, points: 6, bench: 3, isLive: true))
    }

    @Test func theSumMatchesTheCards() {
        let picks = Self.picks(multipliers: [1, 1, 3, 0, 0])
        let cards = picks.picks.map { pick -> (Int, Bool) in
            guard case .points(let points) = Self.live.score(for: pick, team: nil) else { return (0, false) }
            return (points, pick.multiplier == 0)
        }
        let totals = picks.liveTotals(Self.live)
        #expect(totals?.points == cards.filter { !$0.1 }.map(\.0).reduce(0, +))
        #expect(totals?.bench == cards.filter(\.1).map(\.0).reduce(0, +))
    }

    @Test func liveUntilFPLConfirmsTheGameweek() {
        let picks = Self.picks()
        // Every match finished, but bonus and automatic subs aren't confirmed.
        #expect(picks.gameweekPoints(live: Self.live, event: Self.event(finished: true))?.isLive == true)

        let official = GameweekPoints(gameweek: 9, points: 20, bench: 1, isLive: false)
        #expect(picks.gameweekPoints(live: Self.live, event: Self.event(finished: true, dataChecked: true)) == official)
        // Without data_checked, finished decides.
        #expect(picks.gameweekPoints(live: Self.live, event: Self.event(finished: true, dataChecked: nil)) == official)
        #expect(picks.gameweekPoints(live: Self.live, event: Self.event(dataChecked: nil))?.isLive == true)
    }

    @Test func fplsNumbersWhenTheLiveSumCantBeTrusted() {
        let official = GameweekPoints(gameweek: 9, points: 20, bench: 1, isLive: false)
        let picks = Self.picks()
        // The live call failed, the gameweeks haven't loaded, or either is another gameweek's.
        #expect(picks.gameweekPoints(live: nil, event: Self.event()) == official)
        #expect(picks.gameweekPoints(live: Self.live, event: nil) == official)
        #expect(picks.gameweekPoints(live: Self.live, event: Self.event(10)) == official)
        let other = LivePoints(gameweek: 8, elements: [], fixtures: nil)
        #expect(picks.gameweekPoints(live: other, event: Self.event()) == official)
        // A pick with no multiplier could be starting or on the bench.
        let unknown = Self.picks(multipliers: [1, nil, 2, 0, 0])
        #expect(unknown.gameweekPoints(live: Self.live, event: Self.event()) == official)
    }

    @Test func nothingWithoutAGameweekOrPoints() {
        #expect(Self.picks(gameweek: nil).gameweekPoints(live: Self.live, event: Self.event()) == nil)
        let noPoints = ManagerPicks(picks: [], entryHistory: .init(event: 9))
        #expect(noPoints.gameweekPoints(live: nil, event: nil) == nil)
    }

    @Test func decodesDataChecked() throws {
        let json = #"""
        [{"id": 9, "name": "Gameweek 9", "deadline_time": "2026-10-31T11:00:00Z", "finished": true,
          "is_current": true, "is_next": false, "data_checked": false},
         {"id": 8, "name": "Gameweek 8", "deadline_time": "2026-10-24T11:00:00Z", "finished": true,
          "is_current": false, "is_next": false}]
        """#
        let events = try JSONDecoder.fplAPI.decode([Event].self, from: Data(json.utf8))
        #expect(events[0].dataChecked == false && !events[0].isConfirmed)
        #expect(events[1].dataChecked == nil && events[1].isConfirmed)
    }

    @Test func notesShowTheLiveSumForThatGameweekOnly() throws {
        let json = #"""
        {"current": [{"event": 8, "points": 40, "overall_rank": 900, "event_transfers": 0, "event_transfers_cost": 0},
                     {"event": 9, "points": 20, "overall_rank": 700, "event_transfers": 2, "event_transfers_cost": 4}],
         "chips": []}
        """#
        let history = try JSONDecoder.fplAPI.decode(ManagerHistory.self, from: Data(json.utf8))
        let live = GameweekPoints(gameweek: 9, points: 34, bench: 4, isLive: true)

        let current = GameweekScore.score(for: 9, history: history, squad: live)
        #expect(current == GameweekScore(points: 34, isLive: true, hitCost: 4, overallRank: 700, rankChange: 200))
        #expect(current?.accessibilityDescription.hasPrefix("34 points, live, minus 4 for transfers") == true)
        #expect(GameweekScore.score(for: 8, history: history, squad: live) == history.score(for: 8))

        let official = GameweekPoints(gameweek: 9, points: 20, bench: 1, isLive: false)
        #expect(GameweekScore.score(for: 9, history: history, squad: official) == history.score(for: 9))
        #expect(GameweekScore.score(for: 9, history: history, squad: nil) == history.score(for: 9))

        // Right after the deadline the history has no row for the gameweek yet.
        let early = GameweekScore.score(for: 10, history: history,
                                        squad: GameweekPoints(gameweek: 10, points: 3, bench: 0, isLive: true))
        #expect(early == GameweekScore(points: 3, isLive: true, hitCost: 0, overallRank: nil, rankChange: nil))
    }
}

/// The store's number for the team card, the squad header and Notes, against
/// stubbed responses for a live gameweek.
extension StubbedNetworkTests {
    @MainActor @Suite
    struct LiveGameweekTests {
        let client = FPLAPIClient(baseURL: URL(string: "https://stub.test/api")!, session: StubURLProtocol.session)

        /// Gameweek 9 with FPL's numbers behind: 20 points and 1 on the bench.
        static let picks = #"""
        {"picks": [{"element": 1, "position": 1, "multiplier": 1}, {"element": 3, "position": 2, "multiplier": 2},
                   {"element": 4, "position": 12, "multiplier": 0}],
         "entry_history": {"event": 9, "points": 20, "points_on_bench": 1}}
        """#
        static let live = #"""
        [{"id": 1, "total_points": 6, "minutes": 90}, {"id": 3, "total_points": 10, "minutes": 90},
         {"id": 4, "total_points": 3, "minutes": 90}]
        """#

        func stub(live: (Int, String) = (200, LiveGameweekTests.live)) {
            StubURLProtocol.delay = 0
            StubURLProtocol.responses = [
                "/api/managers/1": (200, ManagerTests.response),
                "/api/managers/1/transfers": (200, "[]"),
                "/api/managers/1/history": (200, #"{"current": [], "chips": []}"#),
                "/api/managers/1/picks": (200, Self.picks),
                "/api/events/9/live": live,
                "/api/fixtures": (200, "[]"),
                "/api/elements": (200, "[]"),
            ]
        }

        @Test func theStoreGivesTheLiveSumUntilTheGameweekIsConfirmed() async throws {
            let suite = "FPLTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = LinkedTeamStore(defaults: defaults, client: client)
            store.link(try ManagerTests.manager())
            let playing = [GameweekPointsTests.event()]
            #expect(store.gameweekPoints(events: playing) == nil)

            stub()
            await store.refresh()
            #expect(store.gameweekPoints(events: playing) == GameweekPoints(gameweek: 9, points: 26, bench: 3, isLive: true))

            let official = GameweekPoints(gameweek: 9, points: 20, bench: 1, isLive: false)
            #expect(store.gameweekPoints(events: [GameweekPointsTests.event(finished: true, dataChecked: true)]) == official)
            #expect(store.gameweekPoints(events: []) == official)
        }

        @Test func aFailedLiveCallShowsFPLsNumbers() async throws {
            let suite = "FPLTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = LinkedTeamStore(defaults: defaults, client: client)
            store.link(try ManagerTests.manager())

            stub(live: (503, #"{"detail": "FPL is unavailable right now"}"#))
            await store.refresh()
            #expect(store.gameweekPoints(events: [GameweekPointsTests.event()])
                    == GameweekPoints(gameweek: 9, points: 20, bench: 1, isLive: false))
        }
    }
}
