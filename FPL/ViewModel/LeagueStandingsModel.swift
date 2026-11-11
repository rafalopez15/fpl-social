//
//  LeagueStandingsModel.swift
//  FPL
//

import Foundation
import OSLog

/// A league's standings: pages of 50, stopping after `maxPages`.
/// Each page is a call to FPL, and Overall runs to over 200,000 pages.
@MainActor
final class LeagueStandingsModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded
        /// The first page failed; `notFound` for a league FPL doesn't know.
        case failed(notFound: Bool)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var name: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var standings: [LeagueStanding] = []
    @Published private(set) var newEntries: [LeagueNewEntry] = []
    @Published private(set) var newEntriesHasNext = false
    @Published private(set) var hasNext = false
    /// A later page failed; the list keeps what it has and offers to retry.
    @Published private(set) var moreFailed = false

    /// The top 50, one call to FPL per league opened.
    nonisolated static let defaultMaxPages = 1
    nonisolated static let pageSize = 50

    let maxPages: Int
    /// More teams than are shown: the list ends with a note instead of loading on.
    var isCapped: Bool { hasNext && loadedPages >= maxPages }
    var shownLimit: Int { maxPages * Self.pageSize }

    let leagueID: Int
    private let load: (_ page: Int) async throws -> LeagueStandings
    @Published private var loadedPages = 0
    private var isLoading = false

    init(leagueID: Int, client: FPLAPIClient = FPLAPIClient()) {
        self.leagueID = leagueID
        maxPages = Self.defaultMaxPages
        load = { try await client.league(id: leagueID, page: $0) }
    }

    /// For tests: pages from `load` instead of the API.
    init(leagueID: Int, maxPages: Int = defaultMaxPages, load: @escaping (_ page: Int) async throws -> LeagueStandings) {
        self.leagueID = leagueID
        self.maxPages = maxPages
        self.load = load
    }

    /// Loads the first page once; again after it failed.
    func loadIfNeeded() async {
        guard loadedPages == 0 else { return }
        await loadPage(1)
    }

    /// Reloads from the first page, keeping what's shown until it arrives.
    /// False if it failed, which leaves the list as it was.
    @discardableResult
    func reload() async -> Bool {
        await loadPage(1)
    }

    /// The team's row in the loaded standings, once FPL has ranked it there.
    func standing(of teamID: Int) -> LeagueStanding? {
        standings.first { $0.entry == teamID && ($0.rank ?? 0) > 0 }
    }

    /// The next page, when the last row shows. One at a time; nothing after the last
    /// or past the cap.
    func loadMore() async {
        guard loadedPages > 0, hasNext, !moreFailed, loadedPages < maxPages else { return }
        await loadPage(loadedPages + 1)
    }

    func retryMore() async {
        moreFailed = false
        await loadMore()
    }

    /// False only for a failure; a cancelled load, or one skipped for another running, is true.
    @discardableResult
    private func loadPage(_ page: Int) async -> Bool {
        guard !isLoading else { return true }
        isLoading = true
        defer { isLoading = false }
        if page == 1, loadedPages == 0 { state = .loading }
        do {
            let result = try await load(page)
            if page == 1 {
                standings = []
                moreFailed = false
                newEntries = result.newEntries ?? []
                newEntriesHasNext = result.newEntriesHasNext ?? false
            }
            name = result.name
            lastUpdated = result.lastUpdated
            // Ranks move between pages' requests, so a team can come back on the next page.
            let shown = Set(standings.map(\.entry))
            standings += result.standings.filter { !shown.contains($0.entry) }
            hasNext = result.hasNext
            loadedPages = page
            state = .loaded
            return true
        } catch {
            // Leaving the page cancels its load; that's not a failure to show.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return true }
            Logger.network.notice("Couldn't load page \(page, privacy: .public) of a league: \(error.logSummary, privacy: .public)")
            if page == 1, loadedPages == 0 {
                if case FPLAPIClient.APIError.notFound = error {
                    state = .failed(notFound: true)
                } else {
                    state = .failed(notFound: false)
                }
            } else if page > 1 {
                moreFailed = true
            }
            return false
        }
    }
}
