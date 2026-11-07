//
//  PlayerNotesView.swift
//  FPL
//

import SwiftData
import SwiftUI

/// Every note about one player (FPL-34), grouped by gameweek, newest first:
/// notes he's linked to and transfers that brought him in or sold him. Opened
/// from the stats popover's "All notes about …" row.
struct PlayerNotesView: View {
    let player: NotePlayer

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var gameweeks: GameweekStore
    @EnvironmentObject private var noteSync: NoteSync
    @EnvironmentObject private var account: AccountStore
    @Query private var notes: [Note]
    @State private var editing: Note?
    /// The last deleted note, while its undo toast is showing.
    @State private var deleted: DeletedNote?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sections: [NoteSection] {
        NoteSection.sections(for: notes.filter { $0.isAbout(player.id) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if sections.isEmpty {
                    ContentUnavailableView("No notes about \(player.webName)", systemImage: "note.text",
                                           description: Text("Notes you link him to, and your transfers of him, show here."))
                } else {
                    list
                }
            }
            .themedScreen()
            .overlay(alignment: .bottom) {
                if let deleted {
                    UndoToast(message: "Note deleted") {
                        let note = noteSync.restore(deleted)
                        context.insert(note)
                        noteSync.changed(note)
                        context.saveNotes("Restored a deleted note")
                        withAnimation { self.deleted = nil }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: deleted.id) {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { return }
                        withAnimation { self.deleted = nil }
                    }
                }
            }
            .navigationTitle("Notes about \(player.webName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { note in
                NoteEditorView(note: note)
            }
        }
        // A sheet sits above the tab bar, so lists don't need to clear it.
        .environment(\.tabBarClearance, 0)
        .presentationBackground(Theme.background)
    }

    private var list: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.notes) { note in
                        Button {
                            editing = note
                        } label: {
                            NoteRow(note: note, isDeviceOnly: account.userID != nil && note.accountID == nil)
                        }
                        .foregroundStyle(Theme.text)
                        .themedRow()
                    }
                    .onDelete { offsets in
                        for note in offsets.map({ section.notes[$0] }) {
                            withAnimation { deleted = DeletedNote(note) }
                            noteSync.deleting(note)
                            context.delete(note)
                        }
                        context.saveNotes("Deleted \(offsets.count) note(s)")
                        AccessibilityNotification.Announcement("Note deleted. Undo available.").post()
                    }
                } header: {
                    header(section)
                }
            }
        }
        .listSectionSpacing(12)
        .listStyle(.insetGrouped)
    }

    /// "Gameweek 8" with a lock for past gameweeks, whose notes are read-only.
    private func header(_ section: NoteSection) -> some View {
        let isPast = section.gameweek.map { gameweek in gameweeks.current.map { gameweek < $0 } ?? false } ?? false
        return HStack(spacing: 6) {
            Text(section.title)
            if isPast {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .accessibilityLabel("past gameweek, notes locked")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PlayerNotesView(player: NotePlayer(id: 1, webName: "Rogers"))
        .environmentObject(GameweekStore())
        .environmentObject(AccountStore(auth: nil))
        .environmentObject(NoteSync.preview)
        .modelContainer(NoteSync.preview.container)
}
