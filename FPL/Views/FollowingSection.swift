//
//  FollowingSection.swift
//  FPL
//

import SwiftUI

/// Profile's Following section: the teams you follow by team name, with
/// Unfollow, and "Follow a team". Hidden when the build has no sign-in.
struct FollowingSection: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var teamSync: TeamSync
    @State private var isFollowing = false
    @State private var isSigningIn = false

    static let signInReason = "Sign in to follow teams"

    var body: some View {
        if account.state != .unavailable {
            VStack(alignment: .leading, spacing: 8) {
                Text("FOLLOWING")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(teamSync.following) { team in
                        row(team)
                        Rectangle().fill(Theme.border).frame(height: 1).accessibilityHidden(true)
                    }
                    Button {
                        teamSync.clearError(in: .following)
                        if account.userID == nil { isSigningIn = true } else { isFollowing = true }
                    } label: {
                        HStack {
                            Label("Follow a team", systemImage: "plus")
                                .foregroundStyle(Theme.accent)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let error = teamSync.errors[.following], !isFollowing {
                    TeamErrorLine(error: error)
                        .padding(.horizontal, 4)
                }
            }
            .sheet(isPresented: $isFollowing) {
                FollowTeamSheet()
            }
            .sheet(isPresented: $isSigningIn) {
                SignInView(reason: Self.signInReason)
            }
        }
    }

    private func row(_ team: AccountTeam) -> some View {
        HStack {
            // Until its details load; the API never sends a manager's name.
            Text(teamSync.managers[team.managerId]?.name ?? "Team \(String(team.managerId))")
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Button("Unfollow") {
                Task { await teamSync.unfollow(team.managerId) }
            }
            .buttonStyle(.bordered)
            .disabled(teamSync.isWorking)
        }
        .frame(minHeight: 52)
    }
}

/// Looks a team up by ID and follows it.
private struct FollowTeamSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var teamSync: TeamSync

    var body: some View {
        NavigationStack {
            ScrollView {
                LinkTeamForm(purpose: .follow, error: teamSync.errors[.following], isWorking: teamSync.isWorking,
                             onCancel: { dismiss() },
                             onLink: { manager in Task { if await teamSync.follow(manager) { dismiss() } } })
                .padding(16)
            }
            .themedScreen()
            .navigationTitle("Follow a team")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationBackground(Theme.background)
    }
}

/// A failed team change: yellow for what's on our side or the connection's, red for the rest.
struct TeamErrorLine: View {
    let error: TeamError

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .accessibilityHidden(true)
            Text(error.message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(error == .fplUnavailable || error == .connection ? Theme.warning : Theme.danger)
    }
}
