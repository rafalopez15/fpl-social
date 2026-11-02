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
