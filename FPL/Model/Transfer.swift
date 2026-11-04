//
//  Transfer.swift
//  FPL
//

import Foundation

/// One transfer from `GET /api/managers/{id}/transfers` (newest first).
struct Transfer: Codable, Hashable {
    /// `Element.id` of the player brought in.
    let elementIn: Int
    /// `Element.id` of the player sold.
    let elementOut: Int
    /// The gameweek the transfer counts for, usually the next one.
    let event: Int
    /// When it was made. Has fractional seconds; `JSONDecoder.fplAPI` handles them.
    let time: Date
    /// Price paid for the player in, in tenths of a million.
    let elementInCost: Int?
    /// Selling price of the player out, in tenths of a million.
    let elementOutCost: Int?
    /// A swap undone while planning a Wildcard or Free Hit; the client drops these.
    var isChurn: Bool? = nil
    /// Raw points of the player in and out while the player in was owned, and
    /// their difference. Nil until the gameweek is finished, or if unknown.
    var pointsIn: Int? = nil
    var pointsOut: Int? = nil
    var netPoints: Int? = nil

    /// Net points of the real transfers minus hits taken, for the team card.
    /// Nil without history or when no transfer has points yet.
    static func net(of transfers: [Transfer], history: ManagerHistory?) -> Int? {
        let points = transfers.compactMap(\.netPoints)
        guard let history, !points.isEmpty else { return nil }
        return points.reduce(0, +) - history.current.reduce(0) { $0 + ($1.eventTransfersCost ?? 0) }
    }

    /// "+2 pts", "−5 pts" or "0 pts".
    static func pointsText(_ points: Int) -> String {
        points > 0 ? "+\(points) pts" : points < 0 ? "\u{2212}\(-points) pts" : "0 pts"
    }

    /// "gained 2 points", "lost 5 points" or "no change in points", for VoiceOver.
    static func pointsDescription(_ points: Int) -> String {
        switch points {
        case 0: "no change in points"
        case 1: "gained 1 point"
        case -1: "lost 1 point"
        case let p where p > 0: "gained \(p) points"
        default: "lost \(-points) points"
        }
    }

    /// Transfers made after `date`, oldest first, so a prompt lists them in the order they were made.
    static func made(after date: Date, in transfers: [Transfer]) -> [Transfer] {
        transfers.filter { $0.time > date }.sorted { $0.time < $1.time }
    }
}

/// The transfer a note is about, saved with the note so it shows without
/// loading players or transfers again.
struct NoteTransfer: Codable, Hashable {
    let playerIn: NotePlayer
    let playerOut: NotePlayer
    /// Price paid for the player in, in tenths of a million.
    let cost: Int?
    /// What the player out sold for, in tenths of a million. Can be less than
    /// his price then, since FPL keeps half of any rise. Optional and a `var` so
    /// notes saved before it was added still load (as nil).
    var outCost: Int?
    let time: Date

    /// e.g. "Isak in · Watkins out · £8.6m"
    var summary: String {
        var parts = ["\(playerIn.webName) in", "\(playerOut.webName) out"]
        if let cost { parts.append(String(format: "£%.1fm", Double(cost) / 10)) }
        return parts.joined(separator: " · ")
    }
}
