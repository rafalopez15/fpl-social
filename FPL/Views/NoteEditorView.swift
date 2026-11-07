//
//  NoteEditorView.swift
//  FPL
//

import SwiftData
import SwiftUI

/// Sheet for writing a new note, editing one from the current gameweek, or
/// reading one from a past gameweek.
struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var gameweeks: GameweekStore
    @EnvironmentObject private var noteSync: NoteSync

    /// The note being edited or read, or nil for a new note.
    private let note: Note?
    @State private var text: String
    @State private var players: [NotePlayer]
    /// The gameweek a new note goes in, from the Notes tab's +. Nil means the current one.
    private let newNoteGameweek: Int?
    /// The transfer a new note is about, from Profile's transfer list.
    private let newNoteTransfer: NoteTransfer?
    /// The FPL team that made `newNoteTransfer`.
    private let managerID: Int?
    @FocusState private var isEditorFocused: Bool

    /// - Parameters:
    ///   - note: The note to edit or read. Nil writes a new one.
    ///   - gameweek: The gameweek for a new note. Nil uses the current gameweek.
    ///   - players: Players to link to a new note, e.g. from the stats popover.
    ///   - transfer: Makes a new note a transfer note, e.g. from Profile's transfer list.
    ///     Its player in is linked; pass the transfer's gameweek as `gameweek`.
    ///   - managerID: The FPL team that made `transfer`.
    init(note: Note? = nil, gameweek: Int? = nil, players: [NotePlayer] = [], transfer: NoteTransfer? = nil,
         managerID: Int? = nil) {
        self.note = note
        newNoteGameweek = gameweek
        newNoteTransfer = note == nil ? transfer : nil
        self.managerID = note == nil && transfer != nil ? managerID : nil
        _text = State(initialValue: note?.text ?? "")
        _players = State(initialValue: note?.players ?? transfer.map { [$0.playerIn] } ?? players)
    }

    /// The transfer the note is about, saved or new.
    private var transfer: NoteTransfer? { note?.transfer ?? newNoteTransfer }

    private var gameweek: Int? {
        if let note { return note.gameweek }
        return newNoteGameweek ?? gameweeks.current
    }

    /// A new note for a past gameweek locks as soon as it's saved.
    private var locksOnSave: Bool {
        guard note == nil, let gameweek, let current = gameweeks.current else { return false }
        return gameweek < current
    }

    /// Notes from past gameweeks can be read but not changed.
    private var isReadOnly: Bool {
        guard let note else { return false }
        return note.isLocked(currentGameweek: gameweeks.current)
    }

    /// A transfer note is dated by the transfer, like the ones from the prompt.
    private var date: Date { note?.createdAt ?? newNoteTransfer?.time ?? .now }
    private var placeholder: String {
        if let transfer { return "Why did you bring in \(transfer.playerIn.webName)?" }
        return "What are you thinking?"
    }

    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var title: String {
        if note == nil { return transfer == nil ? "New note" : "Why this transfer?" }
        if transfer != nil { return isReadOnly ? "Transfer note" : "Why this transfer?" }
        return isReadOnly ? "Note" : "Edit note"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tagLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if isReadOnly || locksOnSave {
                        Label(isReadOnly ? "Notes from past gameweeks can't be edited."
                                         : "Notes for past gameweeks can't be edited after saving.",
                              systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let transfer {
                    // A transfer note's players are the transfer itself, not editable chips.
                    TransferLine(transfer: transfer)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if !players.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(players) { player in
                                PlayerChip(player: player, onRemove: isReadOnly ? nil : {
                                    players.removeAll { $0.id == player.id }
                                })
                            }
                        }
                    }
                }

                if isReadOnly {
                    ScrollView {
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } else {
                    editor
                }
            }
            .padding()
            .themedScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isReadOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(!canSave)
                    }
                }
            }
        }
        .presentationBackground(Theme.background)
        .task {
            if !isReadOnly { isEditorFocused = true }
            await gameweeks.loadIfNeeded()
        }
    }

    /// e.g. "Gameweek 10 · 2 Nov"
    private var tagLine: String {
        let day = date.formatted(.dateTime.day().month())
        guard let gameweek else { return day }
        return "Gameweek \(gameweek) · \(day)"
    }

    private var editor: some View {
        TextEditor(text: $text)
            .focused($isEditorFocused)
            .onChange(of: text) {
                if text.unicodeScalars.count > Note.maxTextLength { text = Note.capped(text) }
            }
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Note")
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let note {
            note.text = trimmed
            note.players = players
            note.updatedAt = .now
            noteSync.changed(note)
            context.saveNotes("Edited a note")
        } else {
            let note = Note(text: trimmed, gameweek: gameweek, players: players,
                            transfer: newNoteTransfer, managerID: managerID, createdAt: date)
            context.insert(note)
            noteSync.added(note)
            context.saveNotes("Added a note")
        }
        dismiss()
    }
}

/// A linked player's name, with a button to unlink it when editing.
private struct PlayerChip: View {
    let player: NotePlayer
    /// Nil hides the unlink button.
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Text(player.webName)
                .font(.subheadline.weight(.semibold))
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.secondaryText)
                        // Pad out to a comfortable tap target.
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unlink \(player.webName)")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, onRemove == nil ? 12 : 2)
        .frame(minHeight: 28)
        .background(Theme.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.border) }
    }
}

#Preview {
    NoteEditorView(players: [NotePlayer(id: 1, webName: "Isak")])
        .environmentObject(GameweekStore())
        .environmentObject(NoteSync.preview)
        .modelContainer(NoteSync.preview.container)
}
