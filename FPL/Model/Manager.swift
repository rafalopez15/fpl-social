//
//  Manager.swift
//  FPL
//

import Foundation

/// An FPL manager's team from `GET /api/managers/{id}`. FPL calls this an entry.
///
/// Only `id`, `name` and the manager's names are guaranteed; the rest can be null.
struct Manager: Codable, Identifiable, Hashable {
    /// The manager ID, the number after `/entry/` in FPL URLs.
    let id: Int
    /// Team name, e.g. "Solio Moose".
    let name: String
    let playerFirstName: String
    let playerLastName: String

    let currentEvent: Int?
    let startedEvent: Int?
    /// Team id (1–20), matching `Element.team`.
    let favouriteTeam: Int?
    let playerRegionName: String?
    let summaryOverallPoints: Int?
    let summaryOverallRank: Int?
    let summaryEventPoints: Int?
    let summaryEventRank: Int?
    /// Money in the bank at the last deadline, in tenths of a million.
    let lastDeadlineBank: Int?
    /// Squad value at the last deadline, in tenths of a million.
    let lastDeadlineValue: Int?
    let lastDeadlineTotalTransfers: Int?

    /// e.g. "Chris Musson"
    var managerName: String {
        [playerFirstName, playerLastName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// The team linked on this device, saved so it shows without a network call.
struct LinkedTeam: Codable, Equatable {
    let id: Int
    let teamName: String
    let managerName: String

    init(_ manager: Manager) {
        id = manager.id
        teamName = manager.name
        managerName = manager.managerName
    }

    init(id: Int, teamName: String, managerName: String) {
        self.id = id
        self.teamName = teamName
        self.managerName = managerName
    }
}
