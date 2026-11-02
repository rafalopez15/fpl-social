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

    /// The note being edited or read, or nil for a new note.
    private let note: Note?
    @State private var text: String
    @State private var players: [NotePlayer]
    /// The gameweek a new note goes in, from the Notes tab's +. Nil means the current one.
    private let newNoteGameweek: Int?
    @FocusState private var isEditorFocused: Bool

    /// - Parameters:
    ///   - note: The note to edit or read. Nil writes a new one.
    ///   - gameweek: The gameweek for a new note. Nil uses the current gameweek.
    ///   - players: Players to link to a new note, e.g. from the stats popover.
    init(note: Note? = nil, gameweek: Int? = nil, players: [NotePlayer] = []) {
        self.note = note
        newNoteGameweek = gameweek
        _text = State(initialValue: note?.text ?? "")
        _players = State(initialValue: note?.players ?? players)
    }

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

    private var date: Date { note?.createdAt ?? .now }
    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var title: String {
        if note == nil { return "New note" }
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

                if !players.isEmpty {
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
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("What are you thinking?")
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
        } else {
            context.insert(Note(text: trimmed, gameweek: gameweek, players: players))
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
        .modelContainer(for: Note.self, inMemory: true)
}
