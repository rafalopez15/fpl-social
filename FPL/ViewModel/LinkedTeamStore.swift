//
//  LinkedTeamStore.swift
//  FPL
//

import Foundation

/// The FPL team linked on this device. The link is stored in UserDefaults, so it
/// survives restarts without an account. Shared via the environment so other
/// features (transfer notes, FPL-12) can read the manager ID.
@MainActor
final class LinkedTeamStore: ObservableObject {
    /// The linked team, or nil when none is linked.
    @Published private(set) var linked: LinkedTeam?
    /// The latest details for the linked team (points, rank). Nil until refreshed.
    @Published private(set) var manager: Manager?

    private let defaults: UserDefaults
    private let client: FPLAPIClient
    private static let key = "linkedTeam"

    init(defaults: UserDefaults = .standard, client: FPLAPIClient = FPLAPIClient()) {
        self.defaults = defaults
        self.client = client
        if let data = defaults.data(forKey: Self.key) {
            linked = try? JSONDecoder().decode(LinkedTeam.self, from: data)
        }
    }

    /// Links a team the user has confirmed, replacing any linked before.
    func link(_ manager: Manager) {
        let team = LinkedTeam(manager)
        linked = team
        self.manager = manager
        defaults.set(try? JSONEncoder().encode(team), forKey: Self.key)
    }

    func unlink() {
        linked = nil
        manager = nil
        defaults.removeObject(forKey: Self.key)
    }

    /// Fetches the linked team's latest points and rank. Failures keep what's
    /// shown: the saved names are enough to display the link.
    func refresh() async {
        guard let id = linked?.id, let fresh = try? await client.manager(id: id), linked?.id == id else { return }
        manager = fresh
    }
}
