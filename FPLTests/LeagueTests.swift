//
//  LeagueTests.swift
//  FPLTests
//

import Foundation
import os
import Testing
@testable import FPL

struct LeagueDecodingTests {
    @Test func leaguesDecodeWithUnknownKindsAndMissingFields() throws {
        let json = #"""
        {"id": 1, "name": "Solio Moose", "leagues": [
          {"id": 917411, "name": "testinggg", "kind": "invitational", "size": 1, "rank": 1, "last_rank": 1},
          {"id": 314, "name": "Overall", "kind": "system", "size": 11202041, "rank": 1859157, "last_rank": 1656878},
          {"id": 9, "name": "Later", "kind": "head_to_head", "size": null, "rank": null, "last_rank": null}]}
        """#
        let leagues = try #require(try JSONDecoder.fplAPI.decode(Manager.self, from: Data(json.utf8)).leagues)
        #expect(leagues.map(\.kind) == [.invitational, .system, .unknown])
        #expect(leagues[1].rankChange == -202_279)
        #expect(leagues[2].rankChange == nil)
    }

    @Test func aManagerWithoutLeaguesStillDecodes() throws {
        let manager = try JSONDecoder.fplAPI.decode(Manager.self, from: Data(#"{"id": 1, "name": "Solio Moose"}"#.utf8))
        #expect(manager.leagues == nil)
    }

    @Test func standingsDecodeNewEntriesAndTheirAbsence() throws {
        let json = #"""
        {"id": 2494142, "name": "New league", "last_updated": "2026-11-10T20:29:18Z", "page": 1, "has_next": false,
         "standings": [{"entry": 940727, "entry_name": "Hakuna Mateta", "rank": 0, "last_rank": 0, "total": 0, "event_total": 0}],
         "new_entries": [{"entry": 11270288, "entry_name": "the evanil sons"}], "new_entries_has_next": false}
        """#
        let page = try JSONDecoder.fplAPI.decode(LeagueStandings.self, from: Data(json.utf8))
        #expect(page.newEntries?.map(\.entry) == [11270288])
        #expect(page.lastUpdated != nil)
        // Not ranked yet: no movement.
        #expect(page.standings[0].rankChange == nil)

        let older = #"{"id": 1, "name": "Old API", "page": 1, "has_next": false, "standings": []}"#
        #expect(try JSONDecoder.fplAPI.decode(LeagueStandings.self, from: Data(older.utf8)).newEntries == nil)
    }
}

struct LeagueRankTests {
    @Test func ranksReadExactlyUntilTheyGetLarge() {
        #expect(LeagueRank.text(rank: 3, size: 23) == "3 of 23")
        #expect(LeagueRank.text(rank: 1_859_157, size: 11_202_041)
                == "\(GameweekScore.compact(1_859_157)) of \(GameweekScore.compact(11_202_041))")
        #expect(LeagueRank.text(rank: 12_345, size: nil) == 12_345.formatted())
        #expect(LeagueRank.text(rank: 0, size: 4) == nil)
        #expect(LeagueRank.text(rank: nil, size: 4) == nil)
    }

    @Test func movementIsUpWhenTheRankFalls() {
        #expect(LeagueRank.change(rank: 1, lastRank: 4) == 3)
        #expect(LeagueRank.change(rank: 4, lastRank: 1) == -3)
        #expect(LeagueRank.change(rank: 4, lastRank: 0) == nil)
    }

    @Test func voiceOverReadsRankAndMovement() {
        #expect(LeagueRank.accessibilityText(rank: 3, size: 23, change: 1) == "Rank 3 of 23, up 1 place")
        #expect(LeagueRank.accessibilityText(rank: 3, size: nil, change: -2) == "Rank 3, down 2 places")
        #expect(LeagueRank.accessibilityText(rank: 0, size: 4, change: nil) == "Not ranked yet")
    }

    @Test func theCapNoteGivesTheLeaguesSize() {
        #expect(LeagueRank.capNote(shown: 50, size: 11_202_041) == "Showing the top 50 of \(GameweekScore.compact(11_202_041)) teams")
        #expect(LeagueRank.capNote(shown: 50, size: 2_500) == "Showing the top 50 of \(2_500.formatted()) teams")
        #expect(LeagueRank.capNote(shown: 50, size: nil) == "Showing the top 50 teams")
    }

    @Test func cardSummaryCountsLeagues() {
        #expect(LeaguesCard.summary(count: 0) == "No leagues")
        #expect(LeaguesCard.summary(count: 1) == "1 league")
        #expect(LeaguesCard.summary(count: 24) == "24 leagues")
    }
}

/// Pages served by a test, counting the requests.
final class FakeLeaguePages: @unchecked Sendable {
    struct State {
        var pages: [Int: Result<LeagueStandings, Error>] = [:]
        var requested: [Int] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    var requested: [Int] { lock.withLock { $0.requested } }
    func set(_ page: Int, _ result: Result<LeagueStandings, Error>) { lock.withLock { $0.pages[page] = result } }

    func load(_ page: Int) async throws -> LeagueStandings {
        let result = lock.withLock { state in
            state.requested.append(page)
            return state.pages[page] ?? .failure(FPLAPIClient.APIError.notFound("League not found"))
        }
        return try result.get()
    }

    static func page(_ number: Int, entries: [Int], hasNext: Bool, new: [Int] = []) -> LeagueStandings {
        LeagueStandings(
            id: 7, name: "Mates", lastUpdated: .now, page: number, hasNext: hasNext,
            standings: entries.map {
                LeagueStanding(entry: $0, entryName: "Team \($0)", rank: $0, lastRank: $0, total: 100, eventTotal: 50)
            },
            newEntries: new.map { LeagueNewEntry(entry: $0, entryName: "New \($0)") }, newEntriesHasNext: false)
    }
}

@MainActor
struct LeagueStandingsModelTests {
    let pages = FakeLeaguePages()
    var model: LeagueStandingsModel { LeagueStandingsModel(leagueID: 7, load: pages.load) }
    /// Paging, which the app's one-page cap doesn't reach.
    var pagedModel: LeagueStandingsModel { LeagueStandingsModel(leagueID: 7, maxPages: 2, load: pages.load) }

    @Test func loadsTheFirstPageOnce() async {
        pages.set(1, .success(FakeLeaguePages.page(1, entries: [1, 2], hasNext: false, new: [9])))
        let model = model
        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(model.state == .loaded)
        #expect(model.name == "Mates")
        #expect(model.standings.map(\.entry) == [1, 2])
        #expect(model.newEntries.map(\.entry) == [9])
        #expect(pages.requested == [1])
    }

    @Test func loadsMoreUntilTheLastPage() async {
        pages.set(1, .success(FakeLeaguePages.page(1, entries: [1, 2], hasNext: true)))
        // Ranks moved between requests, so team 2 is on page 2 as well.
        pages.set(2, .success(FakeLeaguePages.page(2, entries: [2, 3], hasNext: false)))
        let model = pagedModel
        await model.loadIfNeeded()
        await model.loadMore()
        await model.loadMore()

        #expect(model.standings.map(\.entry) == [1, 2, 3])
        #expect(!model.hasNext)
        #expect(pages.requested == [1, 2])
    }

    @Test func theAppStopsAtTheTop50() async {
        pages.set(1, .success(FakeLeaguePages.page(1, entries: Array(1...50), hasNext: true)))
        pages.set(2, .success(FakeLeaguePages.page(2, entries: Array(51...100), hasNext: true)))
        let model = model
        await model.loadIfNeeded()
        await model.loadMore()

        #expect(model.standings.count == 50)
        #expect(model.isCapped)
        #expect(model.shownLimit == 50)
        #expect(pages.requested == [1])
    }

    @Test func aCapStopsAfterItsPages() async {
        for page in 1...3 {
            let first = (page - 1) * 50 + 1
            pages.set(page, .success(FakeLeaguePages.page(page, entries: Array(first..<first + 50), hasNext: true)))
        }
        let model = pagedModel
        await model.loadIfNeeded()
        #expect(!model.isCapped)
        await model.loadMore()
        await model.loadMore()

        #expect(model.standings.count == 100)
        #expect(model.isCapped)
        #expect(pages.requested == [1, 2])
    }

    @Test func aLeagueThatEndsAtTheCapIsntCapped() async {
        pages.set(1, .success(FakeLeaguePages.page(1, entries: Array(1...50), hasNext: false)))
        let model = model
        await model.loadIfNeeded()
        #expect(!model.isCapped)
    }

    @Test func aFailedPageKeepsTheListAndRetries() async {
        pages.set(1, .success(FakeLeaguePages.page(1, entries: [1], hasNext: true)))
        pages.set(2, .failure(FPLAPIClient.APIError.dataUnavailable("FPL is unavailable right now")))
        let model = pagedModel
        await model.loadIfNeeded()
        await model.loadMore()
        #expect(model.moreFailed)
        #expect(model.standings.map(\.entry) == [1])

        // Scrolling doesn't retry by itself; the Retry row does.
        await model.loadMore()
        #expect(pages.requested == [1, 2])
        pages.set(2, .success(FakeLeaguePages.page(2, entries: [2], hasNext: false)))
        await model.retryMore()
        #expect(!model.moreFailed)
        #expect(model.standings.map(\.entry) == [1, 2])
    }

    @Test func anUnknownLeagueIsNotFound() async {
        let model = model
        await model.loadIfNeeded()
        #expect(model.state == .failed(notFound: true))
    }

    @Test func aFailedFirstPageCanBeRetried() async {
        pages.set(1, .failure(URLError(.notConnectedToInternet)))
        let model = model
        await model.loadIfNeeded()
        #expect(model.state == .failed(notFound: false))

        pages.set(1, .success(FakeLeaguePages.page(1, entries: [1], hasNext: false)))
        await model.loadIfNeeded()
        #expect(model.state == .loaded)
    }

    @Test func aFailedReloadKeepsTheListAndSaysSo() async {
        pages.set(1, .success(FakeLeaguePages.page(1, entries: [1, 2], hasNext: false)))
        let model = model
        await model.loadIfNeeded()
        pages.set(1, .failure(URLError(.notConnectedToInternet)))

        #expect(await model.reload() == false)
        #expect(model.state == .loaded)
        #expect(model.standings.map(\.entry) == [1, 2])

        pages.set(1, .success(FakeLeaguePages.page(1, entries: [2, 1], hasNext: false)))
        #expect(await model.reload())
    }

    @Test func aReloadClearsAFailedLaterPage() async {
        pages.set(1, .success(FakeLeaguePages.page(1, entries: [1], hasNext: true)))
        pages.set(2, .failure(URLError(.notConnectedToInternet)))
        let model = pagedModel
        await model.loadIfNeeded()
        await model.loadMore()
        #expect(model.moreFailed)

        await model.reload()
        #expect(!model.moreFailed)
    }

    @Test func yourRowIsFoundOnceRanked() async {
        var page = FakeLeaguePages.page(1, entries: [1, 2], hasNext: false)
        pages.set(1, .success(page))
        let model = model
        await model.loadIfNeeded()
        #expect(model.standing(of: 2)?.rank == 2)
        #expect(model.standing(of: 3) == nil)

        // Rank 0: joined this gameweek, not ranked yet.
        page = LeagueStandings(
            id: 7, name: "Mates", lastUpdated: .now, page: 1, hasNext: false,
            standings: [LeagueStanding(entry: 2, entryName: "Team 2", rank: 0, lastRank: 0, total: 0, eventTotal: 0)],
            newEntries: [], newEntriesHasNext: false)
        pages.set(1, .success(page))
        await model.reload()
        #expect(model.standing(of: 2) == nil)
    }

    @Test func reloadingStartsFromTheFirstPage() async {
        pages.set(1, .success(FakeLeaguePages.page(1, entries: [1, 2], hasNext: true)))
        pages.set(2, .success(FakeLeaguePages.page(2, entries: [3], hasNext: false)))
        let model = pagedModel
        await model.loadIfNeeded()
        await model.loadMore()
        pages.set(1, .success(FakeLeaguePages.page(1, entries: [2, 1], hasNext: true)))
        await model.reload()

        #expect(model.standings.map(\.entry) == [2, 1])
        #expect(model.hasNext)
    }
}
