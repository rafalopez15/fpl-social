//
//  History.swift
//  FPL
//

import Foundation

/// A manager's season from `GET /api/managers/{id}/history`: one row per
/// gameweek played and the chips used. Only the fields the app reads are decoded.
struct ManagerHistory: Decodable {
    let current: [GameweekHistory]
    let chips: [ChipUsed]

    /// How a gameweek went, for the Notes tab's gameweek headers. Nil for
    /// gameweeks before the manager joined, or not played yet.
    func score(for gameweek: Int) -> GameweekScore? {
        guard let row = current.first(where: { $0.event == gameweek }) else { return nil }
        let previous = current.first { $0.event == gameweek - 1 }?.overallRank
        return GameweekScore(points: row.points,
                             hitCost: row.eventTransfersCost ?? 0,
                             overallRank: row.overallRank,
                             rankChange: both(previous, row.overallRank).map { $0 - $1 })
    }
}

struct GameweekHistory: Decodable {
    let event: Int
    /// Points that gameweek, before any hit is taken off.
    var points: Int? = nil
    /// Overall rank after the gameweek.
    var overallRank: Int? = nil
    /// Transfers that counted against free transfers. FPL reports 0 in Wildcard
    /// and Free Hit gameweeks.
    let eventTransfers: Int?
    /// Points taken off for extra transfers (4 each).
    var eventTransfersCost: Int? = nil
}

/// A gameweek's result for a gameweek header.
struct GameweekScore: Equatable {
    let points: Int?
    /// Points lost to hits, 0 when none.
    let hitCost: Int
    let overallRank: Int?
    /// Places gained since the gameweek before (positive is up). Nil for the
    /// first gameweek or when a rank is missing.
    let rankChange: Int?
}

private func both(_ a: Int?, _ b: Int?) -> (Int, Int)? {
    guard let a, let b else { return nil }
    return (a, b)
}

struct ChipUsed: Decodable {
    /// FPL's chip code: `wildcard`, `freehit`, `bboost`, `3xc`.
    let name: String
    let event: Int
}

enum FreeTransfers {
    /// FPL lets you save up to 5.
    static let maximum = 5

    /// Free transfers available for the next deadline, worked out from the
    /// season's history because FPL only shares the number with the signed-in
    /// manager. Rules (FPL since 2024/25): the gameweek you join has unlimited
    /// transfers and leaves you 1; each later gameweek you get 1 more, minus
    /// those used (never below 0), up to 5; a Wildcard or Free Hit keeps what
    /// you had without adding 1. Transfers already made for the next gameweek
    /// (`upcoming`) are taken off. Doesn't know about one-off top-ups FPL
    /// sometimes announces. Nil with no history.
    static func available(history: ManagerHistory, upcoming: [Transfer]) -> Int? {
        let gameweeks = history.current.sorted { $0.event < $1.event }
        guard let first = gameweeks.first else { return nil }
        let chipWeeks = Set(history.chips.filter { $0.name == "wildcard" || $0.name == "freehit" }.map(\.event))

        var saved = 1
        for gameweek in gameweeks.dropFirst() {
            // A Wildcard or Free Hit week keeps what was saved but doesn't add one.
            if chipWeeks.contains(gameweek.event) { continue }
            saved = min(maximum, max(0, saved - (gameweek.eventTransfers ?? 0)) + 1)
        }

        let next = (gameweeks.last?.event ?? first.event) + 1
        // Transfers under a chip for the next gameweek don't use free ones.
        guard !chipWeeks.contains(next) else { return saved }
        let made = upcoming.filter { $0.event == next }.count
        return max(0, saved - made)
    }
}
