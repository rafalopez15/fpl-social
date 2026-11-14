//
//  TeamSyncTests.swift
//  FPLTests
//

import Foundation
import os
import Testing
@testable import FPL

/// Stands in for `/api/me/teams` and `/api/managers/{id}`: upserts like the
/// server, newest first, and 409 past 10 teams.
final class FakeTeamsAPI: TeamsAPI, @unchecked Sendable {
    struct State {
        var teams: [AccountTeam] = []
        var puts: [(id: Int, relation: AccountTeam.Relation)] = []
        var deletes: [Int] = []
        var putError: Error?
        /// How many times the teams were listed.
        var lists = 0
        /// Teams whose details fail to load, as when FPL is down.
        var failingManagers: Set<Int> = []
        /// Thrown by `myTeams`, as when offline.
        var listError: Error?
        /// How long `myTeams` takes, so a test can call while a refresh is running.
        var listDelay: Duration?
        /// Lookups of a team's details, and the most running at once.
        var managerCalls = 0
        var running = 0
        var mostRunning = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    var state: State { lock.withLock { $0 } }
    func update(_ change: @Sendable (inout State) -> Void) { lock.withLock { change(&$0) } }

    func myTeams(accessToken: String) async throws -> [AccountTeam] {
        // Read before the delay, as the server answers with the list as it was then.
        let (delay, teams, error) = lock.withLock { state in
            state.lists += 1
            return (state.listDelay, state.teams, state.listError)
        }
        if let delay { try? await Task.sleep(for: delay) }
        if let error { throw error }
        return teams
    }

    func putTeam(id: Int, relation: AccountTeam.Relation, accessToken: String) async throws -> AccountTeam {
        try lock.withLock { state in
            if let error = state.putError { throw error }
            let exists = state.teams.contains { $0.managerId == id }
            if !exists, state.teams.count >= 10 {
                throw FPLAPIClient.APIError.http(status: 409, detail: "Team limit reached")
            }
            state.puts.append((id, relation))
            let team = AccountTeam(managerId: id, relation: relation, createdAt: .now)
            state.teams.removeAll { $0.managerId == id }
            state.teams.insert(team, at: 0)
            return team
        }
    }

    func deleteTeam(id: Int, accessToken: String) async throws {
        update { $0.deletes.append(id); $0.teams.removeAll { $0.managerId == id } }
    }

    func manager(id: Int) async throws -> Manager {
        update { $0.managerCalls += 1; $0.running += 1; $0.mostRunning = max($0.mostRunning, $0.running) }
        defer { update { $0.running -= 1 } }
        // Long enough for lookups started together to overlap.
        try? await Task.sleep(for: .milliseconds(5))
        if state.failingManagers.contains(id) { throw FPLAPIClient.APIError.dataUnavailable("FPL is unavailable") }
        return try TeamSyncTests.manager(id)
    }

    /// Unnamed by default, as before the API's sync names a team.
    static func team(_ id: Int, _ relation: AccountTeam.Relation = .mine, name: String? = nil) -> AccountTeam {
        AccountTeam(managerId: id, relation: relation, createdAt: .now, name: name)
    }
}

@MainActor
struct TeamSyncTests {
    let api = FakeTeamsAPI()
    let defaults: UserDefaults
    let linked: LinkedTeamStore

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "TeamSyncTests.\(UUID().uuidString)"))
        linked = LinkedTeamStore(defaults: defaults)
    }

    nonisolated static func manager(_ id: Int) throws -> Manager {
        try JSONDecoder.fplAPI.decode(Manager.self, from: Data(#"{"id": \#(id), "name": "Club \#(id)"}"#.utf8))
    }

    /// Signed in unless `signedIn` is false.
    func makeSync(signedIn: Bool = true) -> (TeamSync, AccountStore) {
        let account = AccountStore(auth: FakeAuth(email: signedIn ? "a@b.co" : nil)) { _ in AccountStoreTests.account }
        return (TeamSync(account: account, linked: linked, api: api, defaults: defaults), account)
    }

    /// The sign-in's sync runs in its own task, and names load off the main actor.
    func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func aRefreshAskedForMeanwhileWaitsForOneThatStartsAfterIt() async {
        api.update { $0.teams = [FakeTeamsAPI.team(5, name: "Club 5")]; $0.listDelay = .milliseconds(50) }
        let (sync, _) = makeSync()
        let first = Task { await sync.refresh() }
        await waitFor { api.state.lists == 1 }

        // Added on another device after the first refresh read the list, so only
        // the second one sees it.
        api.update { $0.teams.insert(FakeTeamsAPI.team(6, name: "Club 6"), at: 0) }
        await sync.refresh()
        #expect(api.state.lists == 2)
        #expect(sync.mine.map(\.managerId) == [6, 5])
        await first.value
    }

    @Test func linkingSignedOutStaysOnTheDevice() async throws {
        let (sync, _) = makeSync(signedIn: false)
        #expect(await sync.link(try Self.manager(7)))
        #expect(linked.linked?.id == 7)
        #expect(api.state.puts.isEmpty)
    }

    @Test func firstSignInAddsThisDevicesTeamAsYours() async throws {
        let (sync, account) = makeSync(signedIn: false)
        linked.link(try Self.manager(7))

        try await account.verify(email: "a@b.co", code: "123456")
        await waitFor { !sync.myTeams.isEmpty }

        #expect(api.state.puts.map(\.id) == [7])
        #expect(api.state.puts.map(\.relation) == [.mine])
        #expect(sync.myTeams.map(\.id) == [7])
        #expect(linked.linked?.id == 7)
    }

    @Test func signingInShowsTheNewestOfYourTeams() async throws {
        api.update { $0.teams = [FakeTeamsAPI.team(5), FakeTeamsAPI.team(3), FakeTeamsAPI.team(9, .following)] }
        let (sync, account) = makeSync(signedIn: false)

        try await account.verify(email: "a@b.co", code: "123456")
        await waitFor { linked.linked != nil }

        #expect(linked.linked?.id == 5)
        #expect(sync.following.map(\.managerId) == [9])
        #expect(sync.managers[9]?.name == "Club 9")
    }

    @Test func keepsTheTeamShownWhileItsYours() async throws {
        linked.link(try Self.manager(3))
        api.update { $0.teams = [FakeTeamsAPI.team(5), FakeTeamsAPI.team(3)] }
        let (sync, _) = makeSync()
        await sync.refresh()
        #expect(linked.linked?.id == 3)
        #expect(sync.myTeams.map(\.id) == [5, 3])
    }

    @Test func aTeamRemovedElsewhereShowsTheNewest() async throws {
        linked.link(try Self.manager(3))
        api.update { $0.teams = [FakeTeamsAPI.team(5)] }
        let (sync, _) = makeSync()
        await sync.refresh()
        #expect(linked.linked?.id == 5)
    }

    @Test func anAccountWithNoTeamsLeavesTheLinkAlone() async throws {
        linked.link(try Self.manager(3))
        let (sync, _) = makeSync()
        await sync.refresh()
        #expect(linked.linked?.id == 3)
    }

    @Test func addingATeamSignedInSavesItFirst() async throws {
        let (sync, _) = makeSync()
        #expect(await sync.link(try Self.manager(7)))
        #expect(api.state.puts.map(\.id) == [7])
        #expect(linked.linked?.id == 7)
        #expect(sync.mine.map(\.managerId) == [7])
    }

    @Test func aRefusedAddLinksNothing() async throws {
        linked.link(try Self.manager(3))
        api.update { $0.teams = (1...10).map { FakeTeamsAPI.team(100 + $0, .following) } }
        let (sync, _) = makeSync()

        #expect(await !sync.link(try Self.manager(7)))

        #expect(linked.linked?.id == 3)
        #expect(sync.errors[.yourTeams] == .limitReached)
        #expect(sync.errors[.following] == nil)
    }

    @Test func switchesBetweenYourTeams() async throws {
        api.update { $0.teams = [FakeTeamsAPI.team(5), FakeTeamsAPI.team(3)] }
        let (sync, _) = makeSync()
        await sync.refresh()
        sync.show(3)
        #expect(linked.linked?.id == 3)
    }

    @Test func unlinkingSignedInRemovesItAndShowsTheNext() async throws {
        api.update { $0.teams = [FakeTeamsAPI.team(5), FakeTeamsAPI.team(3)] }
        let (sync, _) = makeSync()
        await sync.refresh()

        await sync.unlink()

        #expect(api.state.deletes == [5])
        #expect(linked.linked?.id == 3)
        #expect(sync.mine.map(\.managerId) == [3])
    }

    @Test func followsAndUnfollows() async throws {
        let (sync, _) = makeSync()
        #expect(await sync.follow(try Self.manager(9)))
        #expect(sync.following.map(\.managerId) == [9])
        #expect(sync.isFollowing(9))

        await sync.unfollow(9)
        #expect(sync.following.isEmpty)
        #expect(api.state.deletes == [9])
    }

    @Test func aFailedFirstLoadIsntAnEmptyList() async throws {
        let (sync, _) = makeSync()
        api.update { $0.listError = URLError(.notConnectedToInternet) }
        await sync.refresh()
        #expect(!sync.hasLoaded)
        #expect(sync.loadFailed)

        api.update { $0.listError = nil }
        await sync.refresh()
        #expect(sync.hasLoaded)
        #expect(!sync.loadFailed)
    }

    @Test func undoRefusesWhatsNowYourOwnTeam() async throws {
        api.update { $0.teams = [FakeTeamsAPI.team(9)] }
        let (sync, _) = makeSync()
        await sync.refresh()
        #expect(await !sync.refollow(9))
        #expect(sync.errors[.following] == .alreadyYours)
        #expect(api.state.puts.isEmpty)
    }

    @Test func undoingAnUnfollowFollowsAgain() async throws {
        let (sync, _) = makeSync()
        #expect(await sync.follow(try Self.manager(9)))
        #expect(await sync.unfollow(9))
        #expect(sync.following.isEmpty)

        #expect(await sync.refollow(9))
        #expect(sync.following.map(\.managerId) == [9])
        #expect(api.state.puts.map(\.relation) == [.following, .following])
        // The name is still known for the list.
        #expect(sync.managers[9]?.name == "Club 9")
    }

    @Test func yourOwnTeamCantBeFollowed() async throws {
        api.update { $0.teams = [FakeTeamsAPI.team(5)] }
        let (sync, _) = makeSync()
        await sync.refresh()

        #expect(await !sync.follow(try Self.manager(5)))

        #expect(sync.errors[.following] == .alreadyYours)
        #expect(api.state.puts.isEmpty)
    }

    @Test func theTeamShownCantBeFollowedEvenIfTeamsDidntLoad() async throws {
        let (sync, _) = makeSync()
        linked.link(try Self.manager(5))
        #expect(sync.mine.isEmpty)

        #expect(await !sync.follow(try Self.manager(5)))
        #expect(sync.errors[.following] == .alreadyYours)
        #expect(api.state.puts.isEmpty)
    }

    @Test func unlinkingLoadsTheNextTeamIfNeeded() async throws {
        api.update { $0.teams = [FakeTeamsAPI.team(5), FakeTeamsAPI.team(3)]; $0.failingManagers = [3] }
        let (sync, _) = makeSync()
        await sync.refresh()
        #expect(sync.managers[3] == nil)
        api.update { $0.failingManagers = [] }

        await sync.unlink()
        #expect(linked.linked?.id == 3)
    }

    @Test func signingOutKeepsTheTeamShown() async throws {
        api.update { $0.teams = [FakeTeamsAPI.team(5), FakeTeamsAPI.team(3), FakeTeamsAPI.team(9, .following)] }
        let (sync, account) = makeSync()
        await sync.refresh()

        await account.signOut()

        #expect(linked.linked?.id == 5)
        #expect(sync.teams.isEmpty)
        #expect(sync.myTeams.isEmpty)
    }

    @Test func aDeviceTeamThatCouldntJoinIsTriedAgainAndStaysShown() async throws {
        api.update { $0.teams = [FakeTeamsAPI.team(5)]; $0.putError = URLError(.notConnectedToInternet) }
        let (sync, account) = makeSync(signedIn: false)
        linked.link(try Self.manager(7))

        try await account.verify(email: "a@b.co", code: "123456")
        await waitFor { !sync.myTeams.isEmpty }
        await sync.refresh()
        // Not replaced by the account's team while it waits to join.
        #expect(linked.linked?.id == 7)
        #expect(api.state.puts.isEmpty)

        api.update { $0.putError = nil }
        await sync.refresh()
        #expect(api.state.puts.map(\.id) == [7])
        #expect(linked.linked?.id == 7)
        #expect(sync.mine.map(\.managerId).contains(7))
    }

    @Test func aTeamLeftBySigningOutDoesntJoinTheNextAccount() async throws {
        api.update { $0.teams = [FakeTeamsAPI.team(5)] }
        let (sync, account) = makeSync()
        await sync.refresh()
        await account.signOut()
        #expect(linked.linked?.id == 5)

        // Someone else's account, with no teams.
        api.update { $0.teams = [] }
        try await account.verify(email: "b@b.co", code: "123456")
        await waitFor { api.state.lists >= 2 }

        #expect(api.state.puts.isEmpty)
        #expect(linked.linked?.id == 5)
    }

    @Test func aTeamTheAccountFollowsStaysFollowed() async throws {
        api.update { $0.teams = [FakeTeamsAPI.team(9, .following), FakeTeamsAPI.team(5)] }
        let (sync, account) = makeSync(signedIn: false)
        linked.link(try Self.manager(9))

        try await account.verify(email: "a@b.co", code: "123456")
        await waitFor { linked.linked?.id == 5 }

        #expect(api.state.puts.isEmpty)
        #expect(sync.following.map(\.managerId) == [9])
        #expect(linked.linked?.id == 5)
    }

    @Test func aRefreshAskedForMeanwhileRunsAfter() async {
        let (sync, _) = makeSync()
        async let first: Void = sync.refresh()
        async let second: Void = sync.refresh()
        _ = await (first, second)
        #expect(api.state.lists == 2)
    }

    @Test func aLimitErrorIsWordedPlainly() {
        #expect(TeamError(FPLAPIClient.APIError.http(status: 409, detail: "Team limit reached")).message
                == "You've reached the limit of 1,000 teams.")
        #expect(TeamError(FPLAPIClient.APIError.http(status: 429, detail: "Too many teams added, try again later"))
                == .tooManyAdds)
        #expect(TeamError(URLError(.notConnectedToInternet)) == .connection)
        #expect(TeamError(FPLAPIClient.APIError.notFound("Manager not found")) == .notFound)
        #expect(TeamError(FPLAPIClient.APIError.http(status: 422, detail: nil)) == .notFound)
    }

    @Test func eachAreaWaitsOnlyOnItsOwnChanges() async throws {
        let (sync, _) = makeSync()
        let manager = try Self.manager(9)
        let following = Task { await sync.follow(manager) }
        #expect(!sync.isWorking(in: .yourTeams))
        _ = await following.value
        #expect(!sync.isWorking(in: .following))
    }
}

struct FollowingCardTests {
    @Test func countsTeamsInWords() {
        #expect(FollowingCard.summary(count: 0) == "No teams yet")
        #expect(FollowingCard.summary(count: 1) == "1 team")
        #expect(FollowingCard.summary(count: 3) == "3 teams")
        // Formatted for the device's region, e.g. "1,000" or "1.000".
        #expect(FollowingCard.summary(count: 1000) == "\(1000.formatted()) teams")
    }

    @Test func showsNoCountUntilTheTeamsHaveLoaded() {
        #expect(FollowingCard.status(count: 0, loaded: false, failed: false) == "Loading…")
        #expect(FollowingCard.status(count: 0, loaded: false, failed: true) == "Couldn't load your teams")
        #expect(FollowingCard.status(count: 0, loaded: true, failed: false) == "No teams yet")
    }
}

/// Names from `/api/me/teams`, and lookups for the teams it hasn't named.
@MainActor
struct TeamNameTests {
    let base: TeamSyncTests

    init() throws {
        base = try TeamSyncTests()
    }

    @Test func decodesTheTeamNameWhenTheAPISendsOne() throws {
        let json = #"""
        [{"manager_id": 1, "relation": "mine", "created_at": "2026-11-07T10:00:00.123456Z", "name": "Fantasy FC"},
         {"manager_id": 2, "relation": "following", "created_at": "2026-11-07T10:00:00Z", "name": null},
         {"manager_id": 3, "relation": "following", "created_at": "2026-11-07T10:00:00Z"}]
        """#
        let teams = try JSONDecoder.fplAPI.decode([AccountTeam].self, from: Data(json.utf8))
        #expect(teams.map(\.name) == ["Fantasy FC", nil, nil])
    }

    @Test func namedTeamsNeedNoLookups() async throws {
        base.api.update {
            $0.teams = [FakeTeamsAPI.team(5, name: "Five FC"), FakeTeamsAPI.team(3, name: "Three FC"),
                        FakeTeamsAPI.team(9, .following, name: "Nine FC")]
        }
        let (sync, _) = base.makeSync()
        await sync.refresh()

        #expect(base.api.state.managerCalls == 0)
        #expect(sync.myTeams.map(\.teamName) == ["Five FC", "Three FC"])
        #expect(base.linked.linked == LinkedTeam(id: 5, teamName: "Five FC"))
        #expect(sync.name(of: sync.following[0]) == "Nine FC")
    }

    @Test func onlyUnnamedTeamsAreLookedUp() async throws {
        base.api.update { $0.teams = [FakeTeamsAPI.team(5, name: "Five FC"), FakeTeamsAPI.team(9, .following)] }
        let (sync, _) = base.makeSync()
        await sync.refresh()

        #expect(base.api.state.managerCalls == 1)
        #expect(sync.name(of: sync.following[0]) == "Club 9")
    }

    @Test func atMostFourLookupsRunAtOnce() async throws {
        base.api.update { $0.teams = (1...12).map { FakeTeamsAPI.team(100 + $0, .following) } }
        let (sync, _) = base.makeSync()
        await sync.refresh()

        #expect(base.api.state.managerCalls == 12)
        #expect(base.api.state.mostRunning == TeamSync.maxLookups)
        #expect(sync.following.allSatisfy { sync.name(of: $0) != nil })
    }

    @Test func switchingToANamedTeamNeedsNoDetails() async throws {
        base.api.update {
            $0.teams = [FakeTeamsAPI.team(5, name: "Five FC"), FakeTeamsAPI.team(3, name: "Three FC")]
            $0.failingManagers = [3]
        }
        let (sync, _) = base.makeSync()
        await sync.refresh()

        sync.show(3)
        #expect(base.linked.linked == LinkedTeam(id: 3, teamName: "Three FC"))
    }
}
