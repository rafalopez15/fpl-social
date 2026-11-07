//
//  TeamSync.swift
//  FPL
//

import Foundation
import OSLog

/// The signed-in account's FPL teams: the ones you run and the ones you follow
/// (`/api/me/teams`). Signed in, Profile's team is one of yours, picked on this
/// device; signed out, `LinkedTeamStore` keeps a single team as before.
@MainActor
final class TeamSync: ObservableObject {
    /// The account's teams, newest first. Empty while signed out.
    @Published private(set) var teams: [AccountTeam] = []
    /// Each team's details, for names and for switching to it.
    @Published private(set) var managers: [Int: Manager] = [:]
    /// Where a change was made, so its error shows there.
    enum Area { case yourTeams, following }
    /// The last change that failed in each area, shown until the next one there.
    @Published private(set) var errors: [Area: TeamError] = [:]
    @Published private(set) var isWorking = false

    private let account: AccountStore
    private let linked: LinkedTeamStore
    private let api: any TeamsAPI
    private var isRefreshing = false

    init(account: AccountStore, linked: LinkedTeamStore, api: any TeamsAPI = FPLAPIClient()) {
        self.account = account
        self.linked = linked
        self.api = api
        account.onStateChange { [weak self] old, new in self?.accountChanged(from: old, to: new) }
    }

    var mine: [AccountTeam] { teams.filter { $0.relation == .mine } }
    var following: [AccountTeam] { teams.filter { $0.relation == .following } }

    /// Your teams with names loaded, for the team card's switcher.
    var myTeams: [LinkedTeam] {
        mine.compactMap { managers[$0.managerId].map(LinkedTeam.init) }
    }

    func isFollowing(_ id: Int) -> Bool {
        following.contains { $0.managerId == id }
    }

    /// Loads the account's teams, and shows one of yours on Profile if the one
    /// shown isn't yours any more (removed on another device).
    func refresh() async {
        await refresh(keeping: nil)
    }

    /// Links a team you confirmed. Signed in, it joins the account as yours
    /// first, and if that fails nothing changes. Returns whether it was linked.
    func link(_ manager: Manager) async -> Bool {
        guard account.userID != nil else {
            linked.link(manager)
            return true
        }
        guard let team = await perform(in: .yourTeams, { try await $0.putTeam(id: manager.id, relation: .mine, accessToken: $1) })
        else { return false }
        save(team, manager)
        linked.link(manager)
        Logger.linkedTeam.notice("Added a team to the account")
        return true
    }

    /// Shows another of your teams on Profile.
    func show(_ id: Int) {
        guard let manager = managers[id], linked.linked?.id != id else { return }
        linked.link(manager)
    }

    /// Unlinks the team on Profile. Signed in, it leaves the account and the next
    /// of your teams is shown instead.
    func unlink() async {
        guard let id = linked.linked?.id else { return }
        guard account.userID != nil else {
            linked.unlink()
            return
        }
        guard await perform(in: .yourTeams, { try await $0.deleteTeam(id: id, accessToken: $1) }) != nil else { return }
        teams.removeAll { $0.managerId == id }
        if let next = mine.first, let manager = managers[next.managerId] {
            linked.link(manager)
        } else {
            linked.unlink()
        }
        Logger.linkedTeam.notice("Removed a team from the account")
    }

    /// Returns whether it's followed now. One of your own teams can't be: the
    /// API would turn it into a followed team.
    func follow(_ manager: Manager) async -> Bool {
        guard !mine.contains(where: { $0.managerId == manager.id }) else {
            errors[.following] = .alreadyYours
            return false
        }
        guard let team = await perform(in: .following, { try await $0.putTeam(id: manager.id, relation: .following, accessToken: $1) })
        else { return false }
        save(team, manager)
        Logger.linkedTeam.notice("Followed a team")
        return true
    }

    func unfollow(_ id: Int) async {
        guard await perform(in: .following, { try await $0.deleteTeam(id: id, accessToken: $1) }) != nil else { return }
        teams.removeAll { $0.managerId == id }
        Logger.linkedTeam.notice("Unfollowed a team")
    }

    func clearError(in area: Area) {
        errors[area] = nil
    }

    // MARK: - Private

    private func accountChanged(from old: AccountStore.State, to new: AccountStore.State) {
        switch (old, new) {
        case (.signedOut, .signedIn):
            Task { await signedIn() }
        case (_, .signedIn), (_, .deleting):
            break
        default:
            // Signing out keeps the team on Profile, as a link on this device only.
            teams = []
            managers = [:]
            errors = [:]
        }
    }

    /// A team linked on this device joins the account as yours, without asking:
    /// it's one team id, not anything you wrote.
    private func signedIn() async {
        var keeping: Int?
        if let id = linked.linked?.id {
            do {
                _ = try await account.withAccessToken { [api] in try await api.putTeam(id: id, relation: .mine, accessToken: $0) }
            } catch {
                // Keep showing it rather than switch away from a team the account doesn't have yet.
                keeping = id
                Logger.linkedTeam.notice("Couldn't add this device's team to the account: \(error.logSummary, privacy: .public)")
            }
        }
        await refresh(keeping: keeping)
    }

    private func refresh(keeping: Int?) async {
        guard account.userID != nil, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let teams: [AccountTeam]
        do {
            teams = try await account.withAccessToken { [api] in try await api.myTeams(accessToken: $0) }
        } catch {
            Logger.linkedTeam.notice("Couldn't load the account's teams: \(error.logSummary, privacy: .public)")
            return
        }
        guard account.userID != nil else { return }
        self.teams = teams
        await loadManagers(teams.map(\.managerId))
        guard account.userID != nil else { return }

        let current = linked.linked?.id
        if keeping == nil || current != keeping, !mine.contains(where: { $0.managerId == current }),
           let newest = mine.first, let manager = managers[newest.managerId] {
            linked.link(manager)
        }
    }

    /// Team names come from `/api/managers/{id}`, cached at the CDN. A team that
    /// fails to load is left out of lists until the next refresh.
    private func loadManagers(_ ids: [Int]) async {
        let missing = ids.filter { managers[$0] == nil }
        guard !missing.isEmpty else { return }
        await withTaskGroup(of: Manager?.self) { [api] group in
            for id in missing {
                group.addTask { try? await api.manager(id: id) }
            }
            for await manager in group {
                if let manager { managers[manager.id] = manager }
            }
        }
    }

    private func save(_ team: AccountTeam, _ manager: Manager) {
        teams.removeAll { $0.managerId == team.managerId }
        teams.insert(team, at: 0)
        managers[manager.id] = manager
    }

    /// Runs an account request, setting `error` if it fails. Nil on failure.
    private func perform<T: Sendable>(in area: Area,
                                      _ call: @escaping @Sendable (any TeamsAPI, String) async throws -> T) async -> T? {
        isWorking = true
        defer { isWorking = false }
        errors[area] = nil
        do {
            return try await account.withAccessToken { [api] in try await call(api, $0) }
        } catch {
            errors[area] = TeamError(error)
            Logger.linkedTeam.notice("A team change failed: \(error.logSummary, privacy: .public)")
            return nil
        }
    }
}

extension TeamSync {
    /// For previews: signed out.
    static let preview = TeamSync(account: AccountStore(auth: nil), linked: LinkedTeamStore())
}
