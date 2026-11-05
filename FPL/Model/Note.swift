//
//  Note.swift
//  FPL
//

import Foundation
import OSLog
import SwiftData

/// A personal note, stored on the device with SwiftData. Tagged with the
/// gameweek it was written in and optionally linked to players.
@Model
final class Note {
    var text: String
    /// The current gameweek when the note was written. Nil if gameweeks
    /// couldn't be loaded at the time.
    var gameweek: Int?
    var createdAt: Date
    var updatedAt: Date
    /// Linked players, with their name saved alongside the id so a note can be
    /// shown without loading the player list.
    var players: [NotePlayer]
    /// Set for a transfer note (FPL-12): the transfer it explains. Nil for a free note.
    var transfer: NoteTransfer?

    init(text: String, gameweek: Int?, players: [NotePlayer] = [], transfer: NoteTransfer? = nil,
         createdAt: Date = .now) {
        self.text = text
        self.gameweek = gameweek
        self.players = players
        self.transfer = transfer
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension Note {
    /// Whether the note is from a past gameweek, which makes it read-only.
    /// Notes with no gameweek, or when the current gameweek is unknown, stay editable.
    /// So does a transfer note that was skipped (no text yet): you can still
    /// write it once, but not rewrite it afterwards.
    func isLocked(currentGameweek: Int?) -> Bool {
        guard !text.isEmpty, let gameweek, let currentGameweek else { return false }
        return gameweek < currentGameweek
    }

    /// Whether the note is about a player: he's linked to it, or he's the player
    /// in or out of its transfer. Mentions in the text alone don't count.
    func isAbout(_ elementID: Int) -> Bool {
        players.contains { $0.id == elementID }
            || transfer?.playerIn.id == elementID
            || transfer?.playerOut.id == elementID
    }

    /// The transfer note that matters for a player: the latest transfer that
    /// brought him in or sold him. Nil if you haven't transferred him since linking.
    static func latestTransferNote(for elementID: Int, in notes: [Note]) -> (note: Note, broughtIn: Bool)? {
        notes
            .compactMap { note -> (note: Note, transfer: NoteTransfer)? in
                guard let transfer = note.transfer,
                      transfer.playerIn.id == elementID || transfer.playerOut.id == elementID
                else { return nil }
                return (note, transfer)
            }
            .max { $0.transfer.time < $1.transfer.time }
            .map { ($0.note, $0.transfer.playerIn.id == elementID) }
    }

    /// The note saved for a transfer, matched on gameweek and both players: rows
    /// the API builds for chip weeks can't be matched on time.
    static func forTransfer(_ transfer: Transfer, in notes: [Note]) -> Note? {
        notes.first {
            $0.gameweek == transfer.event
                && $0.transfer?.playerIn.id == transfer.elementIn
                && $0.transfer?.playerOut.id == transfer.elementOut
        }
    }

    /// Your latest transfer of a player, for the stats popover, with its note if
    /// one was written. Uses the season's transfers when loaded, so it covers
    /// transfers from before linking (which have no note); otherwise falls back
    /// to transfer notes. Nil if you haven't transferred him this season.
    static func latestTransfer(for elementID: Int, history: [NamedTransfer]?, notes: [Note]) -> PlayerTransfer? {
        guard let history else {
            return latestTransferNote(for: elementID, in: notes).flatMap { latest in
                latest.note.transfer.map {
                    PlayerTransfer(transfer: $0, gameweek: latest.note.gameweek,
                                   broughtIn: latest.broughtIn, note: latest.note)
                }
            }
        }
        guard let latest = history
            .filter({ $0.transfer.elementIn == elementID || $0.transfer.elementOut == elementID })
            .max(by: { $0.transfer.time < $1.transfer.time })
        else { return nil }
        let note = forTransfer(latest.transfer, in: notes)
        return PlayerTransfer(transfer: latest.noteTransfer, gameweek: latest.transfer.event,
                              broughtIn: latest.transfer.elementIn == elementID, note: note,
                              netPoints: latest.transfer.netPoints)
    }
}

/// A copy of a deleted note, kept briefly so the delete can be undone.
struct DeletedNote: Identifiable {
    let id = UUID()
    let text: String
    let gameweek: Int?
    let players: [NotePlayer]
    let transfer: NoteTransfer?
    let createdAt: Date
    let updatedAt: Date

    init(_ note: Note) {
        text = note.text
        gameweek = note.gameweek
        players = note.players
        transfer = note.transfer
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }

    /// A new note identical to the deleted one, so it returns to the same place.
    func restored() -> Note {
        let note = Note(text: text, gameweek: gameweek, players: players, transfer: transfer, createdAt: createdAt)
        note.updatedAt = updatedAt
        return note
    }
}

/// A player linked to a note.
struct NotePlayer: Codable, Hashable, Identifiable {
    /// `Element.id`
    let id: Int
    let webName: String
}

/// Notes from one gameweek, for the Notes tab's sections.
struct NoteSection: Identifiable {
    let gameweek: Int?
    let notes: [Note]

    var id: Int { gameweek ?? -1 }
    var title: String { gameweek.map { "Gameweek \($0)" } ?? "No gameweek" }

    /// Newest gameweek first, notes without a gameweek last; newest note first within each.
    ///
    /// With `currentGameweek`, every gameweek from it back to 1 gets a section,
    /// empty or not, so the list reads as the whole season so far.
    static func sections(for notes: [Note], currentGameweek: Int? = nil) -> [NoteSection] {
        let byGameweek = Dictionary(grouping: notes, by: \.gameweek)
        var gameweeks = Set(byGameweek.keys)
        if let currentGameweek, currentGameweek >= 1 {
            gameweeks.formUnion((1...currentGameweek).map(Optional.some))
        }
        return gameweeks
            .map { NoteSection(gameweek: $0, notes: (byGameweek[$0] ?? []).sorted { $0.createdAt > $1.createdAt }) }
            .sorted { ($0.gameweek ?? .min) > ($1.gameweek ?? .min) }
    }
}

/// A player's latest transfer as the popover shows it.
struct PlayerTransfer {
    let transfer: NoteTransfer
    let gameweek: Int?
    /// True if the transfer brought the player in, false if it sold him.
    let broughtIn: Bool
    /// The transfer note, or nil for transfers made before linking.
    let note: Note?
    /// The transfer's net points; nil from transfer notes alone or before they're known.
    var netPoints: Int? = nil
}

extension ModelContext {
    /// Saves now rather than at the next autosave, so a failure is logged with
    /// the change that caused it. `change` is logged as public: no note text.
    func saveNotes(_ change: String) {
        do {
            try save()
            Logger.notes.info("\(change, privacy: .public)")
        } catch {
            Logger.notes.error("Couldn't save (\(change, privacy: .public)): \(error.logSummary, privacy: .public) \(error)")
        }
    }
}
