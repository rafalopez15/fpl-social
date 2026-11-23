//
//  ElementStatsView.swift
//  FPL
//

import SwiftData
import SwiftUI

/// Season and advanced stats for one player, shown in a popover from the list.
struct ElementStatsView: View {
    let element: Element
    let team: Team?
    /// The player's team's next gameweeks. Empty hides the section.
    var fixtures: [GameweekFixtures] = []
    /// All teams by id, for opponent short names.
    var teams: [Int: Team] = [:]
    /// The linked team's transfers this season, nil when not loaded or not linked.
    var transfers: [NamedTransfer]? = nil
    /// Shows an "add note" button in the header when set.
    var onAddNote: (() -> Void)? = nil
    /// Shows an "All notes about …" row, when you have notes about the player.
    var onShowNotes: (() -> Void)? = nil
    /// False hides the Season and Advanced stats, for Profile's squad, where
    /// the transfer and fixtures are what matter.
    var showsStats = true

    /// For the transfer note section and the notes count. Few enough to filter in memory.
    @Query private var notes: [Note]

    private var noteCount: Int { notes.filter { $0.isAbout(element.id) }.count }

    var body: some View {
        // 12pt between blocks, with a hairline between sections so each reads as its own group.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(element.fullName)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let selectedBy = element.selectedByPercent {
                        Text(String(format: "Selected by %.1f%%", selectedBy))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let onAddNote {
                    Button(action: onAddNote) {
                        Image(systemName: "square.and.pencil")
                            .font(.title3)
                            // 44pt tap target, nudged so the icon lines up with the name.
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .padding(.top, -10)
                    .padding(.trailing, -10)
                    .accessibilityLabel("Add note about \(element.webName)")
                }
            }

            if element.availabilityFlag != nil || element.currentNews != nil {
                NewsCallout(element: element)
            }

            if let latest = Note.latestTransfer(for: element.id, history: transfers, notes: notes) {
                SectionDivider()
                TransferSection(latest: latest)
            }

            if let onShowNotes, noteCount > 0 {
                SectionDivider()
                AllNotesRow(name: element.webName, count: noteCount, action: onShowNotes)
            }

            if !fixtures.isEmpty {
                SectionDivider()
                FixturesSection(gameweeks: fixtures, teams: teams)
            }

            if showsStats {
                stats
            }
        }
        .padding()
        .frame(width: 300)
    }

    @ViewBuilder
    private var stats: some View {
        SectionDivider()

        StatSection(title: "Season", stats: [
            ("Minutes", int(element.minutes)),
            ("Starts", int(element.starts)),
            ("Goals", int(element.goalsScored)),
            ("Assists", int(element.assists)),
            ("Clean sheets", int(element.cleanSheets)),
            ("Goals conceded", int(element.goalsConceded)),
            ("Saves", int(element.saves)),
            ("Bonus", int(element.bonus)),
            ("Yellow cards", int(element.yellowCards)),
            ("Red cards", int(element.redCards)),
        ])

        SectionDivider()

        StatSection(title: "Advanced", stats: [
            ("xG", decimal(element.expectedGoals, places: 2)),
            ("xA", decimal(element.expectedAssists, places: 2)),
            ("xGI", decimal(element.expectedGoalInvolvements, places: 2)),
            ("xGC", decimal(element.expectedGoalsConceded, places: 2)),
            ("ICT index", decimal(element.ictIndex, places: 1)),
        ])
    }

    /// e.g. "Forward · Man City"
    private var subtitle: String {
        [element.position?.singularTitle, team?.name]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func int(_ value: Int?) -> String {
        value.map(String.init) ?? "–"
    }

    private func decimal(_ value: Double?, places: Int) -> String {
        value.map { String(format: "%.\(places)f", $0) } ?? "–"
    }
}

/// Injury or availability news in the flag's color (yellow doubtful, red out),
/// or grey when the player isn't flagged.
private struct NewsCallout: View {
    let element: Element

    private var flagColor: Color? { element.availabilityFlag.map(Theme.color(for:)) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: flagColor != nil ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(flagColor ?? Theme.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(element.currentNews ?? element.availabilityDescription)
                    .foregroundStyle(flagColor ?? Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let added = element.newsAdded {
                    Text("Updated \(added, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The next gameweeks side by side: each column lists the team's fixtures in
/// that gameweek (opponent, home or away, difficulty chip), or "–" for a blank.
private struct FixturesSection: View {
    let gameweeks: [GameweekFixtures]
    let teams: [Int: Team]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FIXTURES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                ForEach(gameweeks) { gameweek in
                    column(gameweek)
                }
            }
        }
    }

    private func column(_ gameweek: GameweekFixtures) -> some View {
        VStack(spacing: 6) {
            Text("GW\(gameweek.gameweek)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if gameweek.fixtures.isEmpty {
                Text("–")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(gameweek.fixtures) { fixture in
                    VStack(spacing: 4) {
                        Text("\(opponentName(fixture)) (\(fixture.isHome ? "H" : "A"))")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        DifficultyChip(difficulty: fixture.difficulty)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(gameweek))
    }

    private func opponentName(_ fixture: TeamFixture) -> String {
        teams[fixture.opponent]?.shortName ?? "–"
    }

    /// e.g. "Gameweek 10: Hull, home, difficulty 2"
    private func accessibilityLabel(_ gameweek: GameweekFixtures) -> String {
        let fixtures = gameweek.fixtures.map { fixture in
            let name = teams[fixture.opponent]?.name ?? "Unknown team"
            return "\(name), \(fixture.isHome ? "home" : "away"), difficulty \(fixture.difficulty)"
        }
        let detail = fixtures.isEmpty ? "No fixture" : fixtures.joined(separator: "; ")
        return "Gameweek \(gameweek.gameweek): \(detail)"
    }
}

/// FPL's 1–5 fixture difficulty as a colored chip.
struct DifficultyChip: View {
    let difficulty: Int

    var body: some View {
        let colors = Theme.difficultyColors(difficulty)
        Text("\(difficulty)")
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(colors.foreground)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(colors.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Your latest transfer of this player: when you bought or sold him, the
/// price, and your note from that transfer if there is one.
private struct TransferSection: View {
    let latest: PlayerTransfer

    private var heading: String {
        let gameweek = latest.gameweek.map { " in GW\($0)" } ?? ""
        return latest.broughtIn ? "Bought\(gameweek)" : "Sold\(gameweek)"
    }

    /// "£8.0m" when bought, "£8.3m, replaced by Isak" when sold.
    private var detail: String? {
        let transfer = latest.transfer
        let price = (latest.broughtIn ? transfer.cost : transfer.outCost)
            .map { String(format: "£%.1fm", Double($0) / 10) }
        if latest.broughtIn { return price }
        return [price, "replaced by \(transfer.playerIn.webName)"].compactMap { $0 }.joined(separator: ", ")
    }

    /// The net from the player in's side: "+2 pts vs Watkins" when bought,
    /// "Isak +3 pts vs him" when sold. Nil until the gameweek has finished.
    private var net: (points: Int, line: (String) -> String)? {
        guard let points = latest.netPoints else { return nil }
        let transfer = latest.transfer
        return latest.broughtIn
            ? (points, { "\($0) vs \(transfer.playerOut.webName)" })
            : (points, { "\(transfer.playerIn.webName) \($0) vs him" })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(heading.uppercased(), systemImage: latest.broughtIn ? "arrow.down.left" : "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(latest.broughtIn ? Theme.accent : Theme.secondaryText)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let net {
                Text(net.line(PointsLabel.text(net.points)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(PointsLabel.color(net.points))
                    .accessibilityLabel(net.line(PointsLabel.description(net.points)))
            }
            if let note = latest.note {
                if note.text.isEmpty {
                    Text("No note written.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\u{201C}\(note.text)\u{201D}")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "All notes about Rogers (3)", opening the list of them.
private struct AllNotesRow: View {
    let name: String
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label("All notes about \(name) (\(count))", systemImage: "note.text")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Sits flush with the sections above and below despite the 44pt target.
        .padding(.vertical, -8)
        .accessibilityLabel(count == 1 ? "1 note about \(name)" : "All \(count) notes about \(name)")
    }
}

/// A hairline between popover sections.
private struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A titled two-column grid of label/value pairs.
private struct StatSection: View {
    let title: String
    let stats: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(Array(stride(from: 0, to: stats.count, by: 2)), id: \.self) { index in
                    GridRow {
                        cell(stats[index])
                        // Wider gap between the two label/value pairs than within a pair.
                        Color.clear
                            .frame(width: 8, height: 1)
                            .gridCellUnsizedAxes(.vertical)
                        if index + 1 < stats.count {
                            cell(stats[index + 1])
                        }
                    }
                }
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private func cell(_ stat: (label: String, value: String)) -> some View {
        Text(stat.label)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            // Fill the width so every section's columns line up.
            .frame(maxWidth: .infinity, alignment: .leading)
        Text(stat.value)
            .monospacedDigit()
            .fontWeight(.semibold)
            .gridColumnAlignment(.trailing)
    }
}

// MARK: - Presenting

extension View {
    /// The stats popover for `element`, with its note button: tapping it closes
    /// the popover and opens the note editor for the current gameweek with the
    /// player linked. "All notes about …" opens `PlayerNotesView` the same way.
    /// Used by the Players list and Profile's squad, which passes
    /// `showsStats: false` to leave out the season and advanced stats.
    func statsPopover(isPresented: Binding<Bool>, element: Element, team: Team?,
                      fixtures: [GameweekFixtures], teams: [Int: Team],
                      showsStats: Bool = true, arrowEdge: Edge = .leading) -> some View {
        modifier(StatsPopover(isPresented: isPresented, element: element, team: team,
                              fixtures: fixtures, teams: teams, showsStats: showsStats,
                              arrowEdge: arrowEdge))
    }
}

private struct StatsPopover: ViewModifier {
    @Binding var isPresented: Bool
    let element: Element
    let team: Team?
    let fixtures: [GameweekFixtures]
    let teams: [Int: Team]
    let showsStats: Bool
    let arrowEdge: Edge

    /// Passed into the popover explicitly: its content doesn't reliably inherit
    /// the model container, so its transfer-note @Query came back empty.
    @Environment(\.modelContext) private var modelContext
    /// For the popover's transfer section.
    @EnvironmentObject private var linkedTeam: LinkedTeamStore
    /// What the popover asked to open; it opens once the popover has closed.
    @State private var requested: Request?
    @State private var showingNoteEditor = false
    @State private var showingNotes = false

    private enum Request { case newNote, allNotes }

    private var player: NotePlayer { NotePlayer(id: element.id, webName: element.webName) }

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
                ElementStatsView(element: element, team: team, fixtures: fixtures, teams: teams,
                                 transfers: linkedTeam.transferHistory, onAddNote: {
                    requested = .newNote
                    isPresented = false
                }, onShowNotes: {
                    requested = .allNotes
                    isPresented = false
                }, showsStats: showsStats)
                .modelContext(modelContext)
                .presentationBackground(Theme.surface)
                // Show as a popover bubble on iPhone instead of a full sheet.
                .presentationCompactAdaptation(.popover)
            }
            // A sheet can't open while the popover is still on screen, so wait
            // for it to close before showing the note editor or the notes list.
            .onChange(of: isPresented) { _, isShowing in
                guard !isShowing, let request = requested else { return }
                requested = nil
                switch request {
                case .newNote: showingNoteEditor = true
                case .allNotes: showingNotes = true
                }
            }
            .sheet(isPresented: $showingNoteEditor) {
                NoteEditorView(players: [player])
            }
            .sheet(isPresented: $showingNotes) {
                PlayerNotesView(player: player)
            }
    }
}
