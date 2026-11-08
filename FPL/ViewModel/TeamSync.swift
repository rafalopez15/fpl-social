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
    private let defaults: UserDefaults
    private var isRefreshing = false
    private var refreshAgain = false

    /// This device's team, still to be added to the account as yours. Kept until
    /// it is, and shown meanwhile.
    private static let teamToAddKey = "teamToAdd"
    /// True when the device's team was left by signing out, so it's someone's account
    /// team rather than one linked on this device.
    private static let fromAccountKey = "linkedTeamFromAccount"

    init(account: AccountStore, linked: LinkedTeamStore, api: any TeamsAPI = FPLAPIClient(),
         defaults: UserDefaults = .standard) {
        self.account = account
        self.linked = linked
        self.api = api
        self.defaults = defaults
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
        guard account.userID != nil else { return }
        // One at a time; a refresh asked for meanwhile runs once more afterwards.
        guard !isRefreshing else {
            refreshAgain = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            await refreshOnce()
        } while refreshAgain && account.userID != nil
    }

    /// Links a team you confirmed. Signed in, it joins the account as yours
    /// first, and if that fails nothing changes. Returns whether it was linked.
    func link(_ manager: Manager) async -> Bool {
        guard account.userID != nil else {
            linked.link(manager)
            defaults.set(false, forKey: Self.fromAccountKey)
            return true
        }
        guard let team = await perform(in: .yourTeams, { try await $0.putTeam(id: manager.id, relation: .mine, accessToken: $1) })
        else { return false }
        save(team, manager)
        teamToAdd = nil
        linked.link(manager)
        Logger.linkedTeam.notice("Added a team to the account")
        return true
    }

    /// Shows another of your teams on Profile.
    func show(_ id: Int) {
        guard let manager = managers[id], linked.linked?.id != id else { return }
        teamToAdd = nil
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
        teamToAdd = nil
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
            teamToAdd = nil
            if old != .unavailable, linked.linked != nil { defaults.set(true, forKey: Self.fromAccountKey) }
        }
    }

    private var teamToAdd: Int? {
        get { defaults.object(forKey: Self.teamToAddKey) as? Int }
        set { defaults.set(newValue, forKey: Self.teamToAddKey) }
    }

    /// A team linked on this device while signed out joins the account as yours,
    /// without asking: it's one team id, not anything you wrote. One left by
    /// signing out belongs to that account, so it doesn't join this one.
    private func signedIn() async {
        if let id = linked.linked?.id, !defaults.bool(forKey: Self.fromAccountKey) { teamToAdd = id }
        defaults.removeObject(forKey: Self.fromAccountKey)
        await refresh()
    }

    private func refreshOnce() async {
        let teams: [AccountTeam]
        do {
            teams = try await account.withAccessToken { [api] in try await api.myTeams(accessToken: $0) }
        } catch {
            Logger.linkedTeam.notice("Couldn't load the account's teams: \(error.logSummary, privacy: .public)")
            return
        }
        guard account.userID != nil else { return }
        self.teams = teams
        await addTeamToAdd()
        await loadManagers(self.teams.map(\.managerId))
        guard account.userID != nil else { return }

        // A team still waiting to join stays shown; so does any while the transfer
        // prompt is up, which switching would close unsaved.
        let current = linked.linked?.id
        if linked.pendingTransfers.isEmpty, current == nil || current != teamToAdd,
           !mine.contains(where: { $0.managerId == current }),
           let newest = mine.first, let manager = managers[newest.managerId] {
            linked.link(manager)
        }
    }

    /// Adds the device's team unless the account has it already, in either list:
    /// a team the account follows stays followed.
    private func addTeamToAdd() async {
        guard let id = teamToAdd else { return }
        guard !teams.contains(where: { $0.managerId == id }) else {
            teamToAdd = nil
            return
        }
        do {
            let team = try await account.withAccessToken { [api] in
                try await api.putTeam(id: id, relation: .mine, accessToken: $0)
            }
            teams.removeAll { $0.managerId == id }
            teams.insert(team, at: 0)
            teamToAdd = nil
            Logger.linkedTeam.notice("Added this device's team to the account")
        } catch {
            errors[.yourTeams] = TeamError(error)
            Logger.linkedTeam.notice("Couldn't add this device's team to the account: \(error.logSummary, privacy: .public)")
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
