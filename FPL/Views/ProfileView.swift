//
//  ProfileView.swift
//  FPL
//

import SwiftData
import SwiftUI

/// The Profile tab: link your FPL team by manager ID, then see it with options
/// to change or unlink it. Accounts and sign-in come later (FPL-11).
struct ProfileView: View {
    @EnvironmentObject private var teamStore: LinkedTeamStore
    /// True while picking a different team; the current link stays until a new one is confirmed.
    @State private var isChanging = false
    @State private var confirmingUnlink = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let linked = teamStore.linked, !isChanging {
                        LinkedTeamCard(team: linked, manager: teamStore.manager,
                                       freeTransfers: teamStore.freeTransfers) {
                            isChanging = true
                        } onUnlink: {
                            confirmingUnlink = true
                        }

                        SquadSection()

                        TransfersSection(history: teamStore.transferHistory,
                                         net: teamStore.transferNet,
                                         failed: teamStore.transferHistoryFailed) {
                            Task { await teamStore.refresh() }
                        }
                    } else {
                        LinkTeamForm(onCancel: isChanging ? { isChanging = false } : nil) { manager in
                            teamStore.link(manager)
                            isChanging = false
                        }
                    }
                }
                .padding(16)
            }
            .themedScreen()
            // Like Notes: the tab bar says where you are, so no title bar.
            .navigationTitle("Profile")
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Unlink \(teamStore.linked?.teamName ?? "team")?",
                                isPresented: $confirmingUnlink, titleVisibility: .visible) {
                Button("Unlink team", role: .destructive) { teamStore.unlink() }
            } message: {
                Text("You can link it again any time with its manager ID.")
            }
            .task(id: teamStore.linked?.id) {
                await teamStore.refresh()
            }
        }
    }
}

/// The linked team: names, manager ID and this season's points and rank.
private struct LinkedTeamCard: View {
    let team: LinkedTeam
    /// Latest details; nil until refreshed, in which case stats show "–".
    let manager: Manager?
    /// Free transfers for the next deadline; nil until worked out.
    let freeTransfers: Int?
    let onChange: () -> Void
    let onUnlink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR FPL TEAM")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(team.teamName)
                        .font(.title2.weight(.bold))
                    Text("\(team.managerName) · ID \(String(team.id))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                Spacer()

                Menu {
                    Button("Change team", systemImage: "arrow.left.arrow.right", action: onChange)
                    Button("Unlink team", systemImage: "minus.circle", role: .destructive, action: onUnlink)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Team options")
                // Pull the 44pt target into the card's padding so the icon lines up with the top-right corner.
                .padding(.top, -12)
                .padding(.trailing, -12)
            }

            Rectangle().fill(Theme.border).frame(height: 1).accessibilityHidden(true)

            HStack(alignment: .top) {
                stat("Points", manager?.summaryOverallPoints)
                stat("Overall rank", manager?.summaryOverallRank)
                stat(manager?.currentEvent.map { "GW\($0) points" } ?? "Gameweek", manager?.summaryEventPoints)
            }

            HStack(alignment: .top) {
                stat("Team value", money(manager?.lastDeadlineValue))
                stat("In the bank", money(manager?.lastDeadlineBank))
                stat("Free transfers", freeTransfers)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stat(_ label: String, _ value: Int?) -> some View {
        stat(label, value?.formatted())
    }

    /// Tenths of a million as "£102.2m". FPL takes these at the last deadline.
    private func money(_ tenths: Int?) -> String? {
        tenths.map { String(format: "£%.1fm", Double($0) / 10) }
    }

    private func stat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "–")
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The season's transfers, one card per gameweek, latest first. A transfer with
/// a note shows it underneath. Tapping a transfer opens its note, or starts one.
private struct TransfersSection: View {
    let history: [NamedTransfer]?
    /// Hidden while nil.
    let net: Int?
    let failed: Bool
    let onRetry: () -> Void

    @Query private var notes: [Note]
    /// The transfer whose note is open in the editor.
    @State private var editing: NamedTransfer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRANSFERS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let net {
                    // Every transfer's net points minus hits.
                    HStack(spacing: 4) {
                        Text("Net after hits")
                            .foregroundStyle(.secondary)
                        PointsLabel(points: net)
                    }
                    .font(.footnote)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Transfer net after hits: \(PointsLabel.description(net))")
                }
            }

            if let history {
                if history.isEmpty {
                    message("No transfers this season.")
                } else {
                    ForEach(NamedTransfer.byGameweek(history), id: \.gameweek) { group in
                        TransferGameweekCard(gameweek: group.gameweek, transfers: group.transfers, notes: notes) {
                            editing = $0
                        }
                    }
                }
            } else if failed {
                HStack {
                    message("Couldn't load transfers.")
                    Spacer()
                    Button("Retry", action: onRetry)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .sheet(item: $editing) { item in
            NoteEditorView(note: Note.forTransfer(item.transfer, in: notes),
                           gameweek: item.transfer.event,
                           transfer: item.noteTransfer)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

private struct TransferGameweekCard: View {
    let gameweek: Int
    let transfers: [NamedTransfer]
    let notes: [Note]
    let onSelect: (NamedTransfer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gameweek \(gameweek)")
                    .font(.headline)
                Spacer()
                Text(transfers.count == 1 ? "1 transfer" : "\(transfers.count) transfers")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(Array(transfers.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(Theme.border).frame(height: 1).accessibilityHidden(true)
                }
                row(item)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ item: NamedTransfer) -> some View {
        let text = Note.forTransfer(item.transfer, in: notes)?.text ?? ""
        return Button {
            onSelect(item)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    TransferLine(transfer: item.noteTransfer)
                    Spacer()
                    // The chevron says the row opens something: its note, or a new one.
                    HStack(spacing: 6) {
                        if let net = item.transfer.netPoints {
                            PointsLabel(points: net)
                        }
                        Text(item.transfer.time.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if !text.isEmpty {
                    Text("\u{201C}\(text)\u{201D}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(text.isEmpty ? "Write a note about this transfer" : "Opens the note")
    }
}

/// Enter a manager ID, look the team up, and confirm it's yours.
private struct LinkTeamForm: View {
    /// Shown as a Cancel button when changing an existing link.
    let onCancel: (() -> Void)?
    let onLink: (Manager) -> Void

    @StateObject private var model = LinkTeamModel()
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(onCancel == nil ? "Link your FPL team" : "Change team")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("The app reads your transfers so it can ask why you made them. You don't need to sign in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Manager ID", text: $model.idText)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
                    .font(.title3.monospacedDigit())
                    .focused($isFieldFocused)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isError ? Theme.danger : Theme.border)
                    }
                    .accessibilityHint("Digits only")

                if case .failed(let error) = model.state {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(error.message)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.footnote)
                    .foregroundStyle(error == .notFound ? Theme.danger : Theme.warning)
                } else {
                    Text("""
                        On the FPL website, open your team's Points page. Your ID is the number after \
                        /entry/ in the address, e.g. fantasy.premierleague.com/entry/**1234567**/event/9.
                        """)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if case .found(let manager) = model.state {
                ConfirmTeamCard(manager: manager) {
                    onLink(manager)
                } onReject: {
                    model.reject()
                    isFieldFocused = true
                }
            } else {
                Button {
                    isFieldFocused = false
                    Task { await model.lookUp() }
                } label: {
                    Group {
                        if model.state == .loading {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            Text(buttonTitle)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.managerID == nil || model.state == .loading)
            }

            if let onCancel {
                Button("Cancel", action: onCancel)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var isError: Bool {
        if case .failed = model.state { return true }
        return false
    }

    /// "Try again" after a failure that retrying could fix.
    private var buttonTitle: String {
        if case .failed(let error) = model.state, error.canRetry { return "Try again" }
        return "Find team"
    }
}

/// "Is this your team?" with the team and manager name, before saving the link.
private struct ConfirmTeamCard: View {
    let manager: Manager
    let onConfirm: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("IS THIS YOUR TEAM?")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(manager.name)
                    .font(.title3.weight(.bold))
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                Button(action: onReject) {
                    Text("Not my team").frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)

                Button(action: onConfirm) {
                    Text("Link team").frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.6))
        }
    }

    /// e.g. "Chris Musson · 563 pts · Rank 1,571,477"
    private var details: String {
        var parts = [manager.managerName]
        if let points = manager.summaryOverallPoints { parts.append("\(points.formatted()) pts") }
        if let rank = manager.summaryOverallRank { parts.append("Rank \(rank.formatted())") }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    ProfileView()
        .environmentObject(LinkedTeamStore())
        .modelContainer(for: Note.self, inMemory: true)
}
