//
//  SyncedNote.swift
//  FPL
//

import Foundation
import SwiftData

/// The body of `PUT /api/me/notes/{id}`: the whole note as this device has it.
/// The newer `updatedAt` wins on the server.
struct NoteBody: Codable, Equatable, Sendable {
    var text: String
    var gameweek: Int?
    var players: [NotePlayer]
    var transfer: NoteTransfer?
    var managerId: Int?
    var createdAt: Date
    var updatedAt: Date
    /// Set to delete the note; nil brings a deleted one back.
    var deletedAt: Date?
}

extension NoteBody {
    init(_ note: Note) {
        self.init(text: note.text, gameweek: note.gameweek, players: note.players, transfer: note.transfer,
                  managerId: note.managerID, createdAt: note.createdAt, updatedAt: note.updatedAt)
    }

    /// A deleted note: no content, since the server clears it anyway.
    static func tombstone(of note: Note, at date: Date) -> NoteBody {
        NoteBody(text: "", gameweek: note.gameweek, players: [], managerId: note.managerID,
                 createdAt: note.createdAt, updatedAt: date, deletedAt: date)
    }
}

/// A note as the server stores it. A deleted one has `deletedAt` set and no content.
struct RemoteNote: Decodable, Equatable, Sendable {
    let id: UUID
    let text: String
    let gameweek: Int?
    let players: [NotePlayer]
    let transfer: NoteTransfer?
    let managerId: Int?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

/// `GET /api/me/notes`: changes oldest first, and the cursor for the next call.
struct NotesPage: Decodable, Sendable {
    let notes: [RemoteNote]
    let cursor: String
    /// Another page is waiting: call again straight away.
    let more: Bool
}

/// A change to a synced note that hasn't reached the server yet. One per note:
/// a newer change replaces the body, since every write sends the whole note.
@Model
final class PendingNoteWrite {
    var noteID: UUID
    var accountID: UUID
    /// The body's `updatedAt`, to order writes and match them after sending.
    var updatedAt: Date
    /// `NoteBody`, encoded with `JSONEncoder.fplAPI`.
    var body: Data

    init(noteID: UUID, accountID: UUID, updatedAt: Date, body: Data) {
        self.noteID = noteID
        self.accountID = accountID
        self.updatedAt = updatedAt
        self.body = body
    }
}

extension JSONEncoder {
    /// Encoder for fplAPI request bodies: snake_case keys and UTC ISO 8601 dates
    /// with milliseconds, which the API requires to have a timezone.
    static var fplAPI: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }
}
