//
//  ProfileView.swift
//  FPL
//

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
                        LinkedTeamCard(team: linked, manager: teamStore.manager)

                        VStack(spacing: 8) {
                            Button {
                                isChanging = true
                            } label: {
                                Text("Change team").frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                confirmingUnlink = true
                            } label: {
                                Text("Unlink team").frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.danger)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            Rectangle().fill(Theme.border).frame(height: 1).accessibilityHidden(true)

            HStack(alignment: .top) {
                stat("Points", manager?.summaryOverallPoints)
                stat("Overall rank", manager?.summaryOverallRank)
                stat(manager?.currentEvent.map { "GW\($0) points" } ?? "Gameweek", manager?.summaryEventPoints)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stat(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value?.formatted() ?? "–")
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
                    Text("On the FPL website, open your team's Points page. Your ID is the number after /entry/ in the address, e.g. fantasy.premierleague.com/entry/**1234567**/event/9.")
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
}
