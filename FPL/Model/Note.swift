//
//  Note.swift
//  FPL
//

import Foundation
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

    init(text: String, gameweek: Int?, players: [NotePlayer] = [], createdAt: Date = .now) {
        self.text = text
        self.gameweek = gameweek
        self.players = players
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension Note {
    /// Whether the note is from a past gameweek, which makes it read-only.
    /// Notes with no gameweek, or when the current gameweek is unknown, stay editable.
    func isLocked(currentGameweek: Int?) -> Bool {
        guard let gameweek, let currentGameweek else { return false }
        return gameweek < currentGameweek
    }
}

/// A copy of a deleted note, kept briefly so the delete can be undone.
struct DeletedNote: Identifiable {
    let id = UUID()
    let text: String
    let gameweek: Int?
    let players: [NotePlayer]
    let createdAt: Date
    let updatedAt: Date

    init(_ note: Note) {
        text = note.text
        gameweek = note.gameweek
        players = note.players
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }

    /// A new note identical to the deleted one, so it returns to the same place.
    func restored() -> Note {
        let note = Note(text: text, gameweek: gameweek, players: players, createdAt: createdAt)
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
