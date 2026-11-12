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
    /// For your points and rank in each gameweek header, when a team is linked.
    @EnvironmentObject private var linkedTeam: LinkedTeamStore
    @EnvironmentObject private var noteSync: NoteSync
    @EnvironmentObject private var account: AccountStore
    @Query private var notes: [Note]
    @State private var editor: EditorTarget?
    @State private var isSigningIn = false
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
                        let note = noteSync.restore(deleted)
                        context.insert(note)
                        noteSync.changed(note)
                        context.saveNotes("Restored a deleted note")
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
            // No title bar: the tab bar already says this is Notes, so the list
            // starts at the top. The title stays for accessibility and future pushes.
            .navigationTitle("Notes")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editor) { target in
                NoteEditorView(note: target.note, gameweek: target.gameweek)
            }
            .sheet(isPresented: $isSigningIn) {
                SignInView(reason: SyncInvitation.reason)
            }
        }
    }

    private var list: some View {
        List {
            // Hidden in builds without sign-in, where state is .unavailable.
            if account.state == .signedOut {
                Section {
                    Button {
                        isSigningIn = true
                    } label: {
                        SyncInvitation()
                    }
                    .foregroundStyle(Theme.text)
                    .themedRow()
                }
            }

            if notes.isEmpty {
                // Goes away once you've written your first note.
                Text("Tap + on a gameweek to write down what you're thinking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }

            // One card per gameweek: the header is the card's first row, so swipe
            // to delete, undo and VoiceOver keep working as a normal list.
            let squadPoints = linkedTeam.gameweekPoints(events: gameweeks.events)
            ForEach(NoteSection.sections(for: notes, currentGameweek: gameweeks.current)) { section in
                Section {
                    GameweekHeader(section: section,
                                   currentGameweek: gameweeks.current,
                                   deadline: section.gameweek.flatMap(gameweeks.deadline(for:)),
                                   score: section.gameweek.flatMap {
                                       GameweekScore.score(for: $0, history: linkedTeam.history, squad: squadPoints)
                                   }) { gameweek in
                        editor = EditorTarget(gameweek: gameweek)
                    }
                    .themedRow()

                    ForEach(section.notes) { note in
                        Button {
                            editor = EditorTarget(note: note)
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
                }
            }
        }
        .listSectionSpacing(12)
        // The grouped style's default top inset leaves a large empty band.
        .contentMargins(.top, 8, for: .scrollContent)
        .listStyle(.insetGrouped)
    }
}

/// The signed-out Notes tab's first row, which opens the sign-in sheet. It stays
/// until you sign in: one compact row, with no close button to keep track of.
private struct SyncInvitation: View {
    static let reason = "Sign in to sync your notes across devices"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(Self.reason)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens sign in")
    }
}

/// A bar confirming a delete or an unfollow, with an Undo button. Used by the Notes
/// tab, `PlayerNotesView` and the Following page.
struct UndoToast: View {
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

/// A gameweek card's first row: the title with a "This week" tag or a lock,
/// the deadline and note count, and a + to add a note. Empty gameweeks get a
/// muted title so the ones with notes stand out when scanning the season.
private struct GameweekHeader: View {
    let section: NoteSection
    let currentGameweek: Int?
    let deadline: Date?
    /// Your points and rank that gameweek; nil with no team linked.
    let score: GameweekScore?
    let onAdd: (Int) -> Void

    private var isCurrent: Bool { section.gameweek != nil && section.gameweek == currentGameweek }

    private var isPast: Bool {
        guard let gameweek = section.gameweek, let currentGameweek else { return false }
        return gameweek < currentGameweek
    }

    /// e.g. "Deadline Sat, Nov 7 · 2 notes"
    private var detail: String? {
        var parts: [String] = []
        if let deadline {
            parts.append("Deadline \(deadline.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
        }
        switch section.notes.count {
        case 0: break
        case 1: parts.append("1 note")
        default: parts.append("\(section.notes.count) notes")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(section.notes.isEmpty ? Theme.secondaryText : Theme.text)
                    if isCurrent {
                        Text("This week")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    } else if isPast {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if let score, score.points != nil {
                ScoreColumn(score: score)
            }

            if let gameweek = section.gameweek {
                Button {
                    onAdd(gameweek)
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .padding(.trailing, -10)
                .accessibilityLabel("Add note to \(section.title)")
            }
        }
        .padding(.vertical, -4)
    }

    /// e.g. "Gameweek 8, past gameweek, notes locked. Deadline Sat, Oct 25 · 1 note"
    private var accessibilityLabel: String {
        var label = section.title
        if isCurrent { label += ", this week" }
        if isPast { label += ", past gameweek, notes locked" }
        if let detail { label += ". \(detail)" }
        if let score { label += ". \(score.accessibilityDescription)" }
        return label
    }
}

/// Points over overall rank, at the right of a gameweek header: "56 pts" and
/// "▲ 338K". The arrow is green up, red down, so the shape and color both tell it.
private struct ScoreColumn: View {
    let score: GameweekScore
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Beside the points the tag squeezes the title from this size up.
    private var tagGoesUnder: Bool { typeSize >= .xLarge }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                if score.isLive, !tagGoesUnder { LiveTag() }
                if score.hitCost > 0 {
                    Text("−\(score.hitCost)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.danger)
                }
                Text("\(score.points ?? 0) pts")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            if let rank = score.overallRank {
                HStack(spacing: 3) {
                    if let change = score.rankChange, change != 0 {
                        Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(change > 0 ? Theme.accent : Theme.danger)
                    }
                    Text(GameweekScore.compact(rank))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if score.isLive, tagGoesUnder { LiveTag() }
        }
        // The header's label already reads these out.
        .accessibilityHidden(true)
    }
}

extension GameweekScore {
    /// 337,752 as "338K", 7,045,139 as "7.05M".
    static func compact(_ rank: Int) -> String {
        rank.formatted(.number.notation(.compactName).precision(.significantDigits(3)))
    }

    /// e.g. "56 points, minus 4 for transfers. Overall rank 337,752, up 178,000 places"
    var accessibilityDescription: String {
        var parts: [String] = []
        if let points {
            let points = isLive ? "\(points) points, live" : "\(points) points"
            parts.append(hitCost > 0 ? "\(points), minus \(hitCost) for transfers" : points)
        }
        if let overallRank {
            var rank = "Overall rank \(overallRank.formatted())"
            if let rankChange, rankChange != 0 {
                rank += ", \(rankChange > 0 ? "up" : "down") \(abs(rankChange).formatted()) places"
            }
            parts.append(rank)
        }
        return parts.joined(separator: ". ")
    }
}

/// A note in the list: for a transfer note, the transfer first; then up to three
/// lines of text (or a prompt to write it, if skipped), then players and the date.
/// Also used by `PlayerNotesView`.
struct NoteRow: View {
    let note: Note
    /// Signed in, and the note isn't in the account: it doesn't sync.
    var isDeviceOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let transfer = note.transfer {
                TransferLine(transfer: transfer)
            }
            if note.text.isEmpty, let transfer = note.transfer {
                Text("Why did you bring in \(transfer.playerIn.webName)? Tap to write it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(note.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { detailLine }
                VStack(alignment: .leading, spacing: 2) { detailLine }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var detailLine: some View {
        Text(detail)
        if isDeviceOnly {
            HStack(spacing: 3) {
                Image(systemName: "iphone")
                    .accessibilityHidden(true)
                Text("On this iPhone only")
            }
            .fixedSize()
        }
    }

    /// e.g. "Isak, Salah · 2 Nov". Transfer notes show only the date; the transfer names the players.
    private var detail: String {
        let day = note.createdAt.formatted(.dateTime.day().month())
        guard note.transfer == nil else { return day }
        let names = note.players.map(\.webName).joined(separator: ", ")
        return names.isEmpty ? day : "\(names) · \(day)"
    }
}

#Preview {
    NotesView()
        .environmentObject(GameweekStore())
        .environmentObject(LinkedTeamStore())
        .environmentObject(AccountStore(auth: nil))
        .environmentObject(NoteSync.preview)
        .modelContainer(NoteSync.preview.container)
}
