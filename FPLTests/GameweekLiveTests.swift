//
//  GameweekLiveTests.swift
//  FPLTests
//

import Foundation
import Testing
@testable import FPL

/// The Gameweek tab while matches are on: the API's saved copy when FPL is down,
/// and when the gameweek reloads itself.
@MainActor
struct GameweekLiveTests {
    private typealias Base = GameweekFixturesTests

    // MARK: A saved copy

    @Test func readsWhenASavedCopyWasFetched() throws {
        func response(_ headers: [String: String]) throws -> HTTPURLResponse {
            try #require(HTTPURLResponse(url: URL(string: "https://stub.test/api/events/10/fixtures")!,
                                         statusCode: 200, httpVersion: nil, headerFields: headers))
        }
        let halfPastOne = Base.time(day: 13, hour: 13, minute: 28)
        #expect(FPLAPIClient.staleAsOf(in: try response(["X-Data-Stale-As-Of": "2026-11-13T13:28:00+00:00"])) == halfPastOne)
        // Python's isoformat adds microseconds, and an offset moves the hour.
        #expect(FPLAPIClient.staleAsOf(in: try response(["x-data-stale-as-of": "2026-11-13T14:28:00.000000+01:00"]))
                == halfPastOne)
        #expect(FPLAPIClient.staleAsOf(in: try response([:])) == nil)
        #expect(FPLAPIClient.staleAsOf(in: try response(["X-Data-Stale-As-Of": "yesterday"])) == nil)
    }

    @Test func aSavedCopyIsMarkedUntilAFreshAnswer() async {
        let asOf = Base.time(hour: 13, minute: 28)
        var isDown = true
        let model = GameweekFixturesModel(staleAsOf: { isDown && $0 == 10 ? asOf : nil }, load: { _ in [Base.live] })
        await model.select(10)
        #expect(model.state == .loaded)
        #expect(model.fixtures == [Base.live])
        #expect(model.staleAsOf == asOf)

        // It belongs to that gameweek: another one's fresh answer isn't marked.
        await model.select(11)
        #expect(model.staleAsOf == nil)
        isDown = false
        await model.select(10)
        #expect(model.staleAsOf == nil)
    }

    @Test func aSavedCopysLineAndRows() {
        #expect(GameweekView.staleLine(asOf: Base.time(hour: 13, minute: 28), timeZone: Base.utc)
            .hasPrefix("FPL is updating · showing scores as of 1:28"))
        let read = FixtureRow.description(of: Base.live, home: "Arsenal", away: "Chelsea", isStale: true)
        #expect(read == "Arsenal 1, Chelsea 0, last known score")
        // Only a match in play changes: full time is still full time.
        #expect(FixtureRow.description(of: Base.played, home: "Arsenal", away: "Chelsea", isStale: true)
                == "Arsenal 2, Chelsea 1, full time")
    }

    // MARK: Refreshing itself

    @Test func reloadsAMinuteAfterTheLastLoadWhileAMatchIsLive() async {
        var clock = Base.time(hour: 15)
        var fixtures = [Base.played, Base.live]
        let model = GameweekFixturesModel(now: { clock }, load: { _ in fixtures })
        #expect(model.refreshDelay(now: clock) == nil)

        await model.select(10)
        #expect(model.refreshesItself)
        #expect(model.refreshDelay(now: clock) == 60)
        #expect(model.refreshDelay(now: clock + 45) == 15)
        // Back on the tab after a while: straight away.
        #expect(model.refreshDelay(now: clock + 300) == 0)

        // Full time everywhere: nothing left to follow.
        clock += 60
        fixtures = [Base.played]
        await model.reload()
        #expect(!model.refreshesItself)
        #expect(model.refreshDelay(now: clock) == nil)
    }

    @Test func upcomingAndPostponedMatchesDontRefresh() async {
        let model = GameweekFixturesModel { _ in [Base.upcoming, Base.postponed, Base.played] }
        await model.select(10)
        #expect(!model.refreshesItself)
    }

    @Test func aSavedCopyKeepsRefreshingWithNoMatchLive() async {
        let model = GameweekFixturesModel(staleAsOf: { _ in Base.time(hour: 13) }, load: { _ in [Base.upcoming] })
        await model.select(10)
        #expect(model.refreshesItself)
    }

    @Test func aFailedRefreshWaitsAMinuteAndSaysItCouldntUpdate() async {
        var clock = Base.time(hour: 15)
        var fails = false
        let model = GameweekFixturesModel(now: { clock }, load: { _ in
            if fails { throw Base.Failure() }
            return [Base.live]
        })
        await model.select(10)
        #expect(!model.couldntUpdate)

        fails = true
        clock += 60
        await model.reload()
        #expect(model.couldntUpdate)
        #expect(model.fixtures == [Base.live])
        // Not again at once: the failed try counts as the last one.
        #expect(model.refreshDelay(now: clock) == 60)

        fails = false
        await model.reload()
        #expect(!model.couldntUpdate)
    }
}
