//
//  ProfileView.swift
//  FPL
//

import SwiftData
import SwiftUI

/// The Profile tab: link your FPL team by manager ID, then see it with options
/// to change or unlink it. The Account card under it signs you in or out, and
/// signed in, Following lists the teams you follow.
struct ProfileView: View {
    @EnvironmentObject private var teamStore: LinkedTeamStore
    @EnvironmentObject private var teamSync: TeamSync
    @EnvironmentObject private var account: AccountStore
    /// True while picking a different team (signed out) or adding one (signed in);
    /// the current one stays until a new one is confirmed.
    @State private var isChanging = false
    @State private var confirmingUnlink = false

    private var isSignedIn: Bool { account.userID != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let linked = teamStore.linked, !isChanging {
                        LinkedTeamCard(team: linked, manager: teamStore.manager,
                                       freeTransfers: teamStore.freeTransfers,
                                       myTeams: isSignedIn ? teamSync.myTeams : [], isSignedIn: isSignedIn) {
                            isChanging = true
                        } onShow: { id in
                            teamSync.show(id)
                        } onUnlink: {
                            confirmingUnlink = true
                        }
                        if let error = teamSync.errors[.yourTeams] {
                            TeamErrorLine(error: error)
                        }

                        AccountCard()

                        FollowingSection()

                        SquadSection()

                        TransfersSection(managerID: linked.id,
                                         history: teamStore.transferHistory,
                                         net: teamStore.transferNet,
                                         failed: teamStore.transferHistoryFailed) {
                            Task { await teamStore.refresh() }
                        }
                    } else {
                        LinkTeamForm(purpose: isChanging ? (isSignedIn ? .add : .change) : .link,
                                     error: teamSync.errors[.yourTeams], isWorking: teamSync.isWorking,
                                     onCancel: isChanging ? { isChanging = false; teamSync.clearError(in: .yourTeams) } : nil) { manager in
                            Task { if await teamSync.link(manager) { isChanging = false } }
                        }

                        AccountCard()

                        FollowingSection()
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
                Button("Unlink team", role: .destructive) { Task { await teamSync.unlink() } }
            } message: {
                Text(isSignedIn ? "It's removed from your account. You can add it again any time with its manager ID."
                                : "You can link it again any time with its manager ID.")
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
    /// Signed in, your teams on the account, to switch between.
    let myTeams: [LinkedTeam]
    let isSignedIn: Bool
    /// Signed out, picks a different team; signed in, adds another.
    let onChange: () -> Void
    let onShow: (Int) -> Void
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
                    Text("ID \(String(team.id))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                Spacer()

                Menu {
                    if myTeams.count > 1 {
                        Section {
                            ForEach(myTeams, id: \.id) { other in
                                Button {
                                    onShow(other.id)
                                } label: {
                                    if other.id == team.id {
                                        Label(other.teamName, systemImage: "checkmark")
                                    } else {
                                        Text(other.teamName)
                                    }
                                }
                            }
                        }
                    }
                    if isSignedIn {
                        Button("Add another team", systemImage: "plus", action: onChange)
                    } else {
                        Button("Change team", systemImage: "arrow.left.arrow.right", action: onChange)
                    }
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
                stat("Squad value", money(manager?.squadValue))
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
    let managerID: Int
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
                           transfer: item.noteTransfer,
                           managerID: managerID)
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

#Preview {
    ProfileView()
        .environmentObject(LinkedTeamStore())
        // No sign-in in previews: they can't reach a preview API, so the card stays hidden.
        .environmentObject(AccountStore(auth: nil))
        .environmentObject(TeamSync.preview)
        .environmentObject(NoteSync.preview)
        .modelContainer(NoteSync.preview.container)
}
