//
//  NotesView.swift
//  FPL
//

import SwiftData
import SwiftUI

/// The Notes tab: every gameweek of the season so far, newest first, each with
/// a + to add a note to it. Transfer notes come later (FPL-12).
struct NotesView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var gameweeks: GameweekStore
    @Query private var notes: [Note]
    @State private var editor: EditorTarget?
    /// The last deleted note, while its undo toast is showing.
    @State private var deleted: DeletedNote?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabBarClearance) private var tabBarClearance

    /// What the editor sheet opens: an existing note, or a new one for a gameweek.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        var note: Note? = nil
        var gameweek: Int? = nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if gameweeks.current == nil && notes.isEmpty {
                    // The list is built from gameweeks, so there's nothing to show without them.
                    if !gameweeks.didFail {
                        ProgressView()
                    } else {
                        ContentUnavailableView {
                            Label("Couldn't load gameweeks", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text("Check your connection and try again.")
                        } actions: {
                            Button("Retry") { Task { await gameweeks.loadIfNeeded() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    list
                }
            }
            .themedScreen()
            .overlay(alignment: .bottom) {
                if let deleted {
                    UndoToast(message: "Note deleted") {
                        context.insert(deleted.restored())
                        withAnimation { self.deleted = nil }
                    }
                    .padding(.horizontal, 16)
                    // The screen runs under the tab bar, so sit just above it.
                    .padding(.bottom, tabBarClearance + 4)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    // Long enough to notice and reach for Undo. A newer delete restarts it.
                    .task(id: deleted.id) {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { return }
                        withAnimation { self.deleted = nil }
                    }
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editor) { target in
                NoteEditorView(note: target.note, gameweek: target.gameweek)
            }
        }
    }

    private var list: some View {
        List {
            if notes.isEmpty {
                // Goes away once you've written your first note.
                Text("Tap + on a gameweek to write down what you're thinking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }

            ForEach(NoteSection.sections(for: notes, currentGameweek: gameweeks.current)) { section in
                Section {
                    ForEach(section.notes) { note in
                        Button {
                            editor = EditorTarget(note: note)
                        } label: {
                            NoteRow(note: note)
                        }
                        .foregroundStyle(Theme.text)
                        .themedRow()
                    }
                    .onDelete { offsets in
                        for note in offsets.map({ section.notes[$0] }) {
                            withAnimation { deleted = DeletedNote(note) }
                            context.delete(note)
                        }
                        AccessibilityNotification.Announcement("Note deleted. Undo available.").post()
                    }
                } header: {
                    SectionHeader(section: section) { gameweek in
                        editor = EditorTarget(gameweek: gameweek)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// A bar confirming a delete, with an Undo button.
private struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(.subheadline)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.border)
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}

/// "Gameweek 9" with a + on the right to add a note to it. Notes with no
/// gameweek get a plain header.
private struct SectionHeader: View {
    let section: NoteSection
    let onAdd: (Int) -> Void

    var body: some View {
        HStack {
            Text(section.title)
            Spacer()
            if let gameweek = section.gameweek {
                Button {
                    onAdd(gameweek)
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        // 44pt tap target without making the header taller.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .padding(.vertical, -12)
                .padding(.trailing, -12)
                .accessibilityLabel("Add note to \(section.title)")
            }
        }
    }
}

/// A note in the list: up to three lines of text, then linked players and the date.
private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.text)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// e.g. "Isak, Salah · 2 Nov"
    private var detail: String {
        let day = note.createdAt.formatted(.dateTime.day().month())
        let names = note.players.map(\.webName).joined(separator: ", ")
        return names.isEmpty ? day : "\(names) · \(day)"
    }
}

#Preview {
    NotesView()
        .environmentObject(GameweekStore())
        .modelContainer(for: Note.self, inMemory: true)
}
