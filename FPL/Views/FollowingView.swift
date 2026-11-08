//
//  FollowingView.swift
//  FPL
//

import SwiftUI

/// Profile's Following card: how many teams you follow, opening the Following page.
/// Signed out it offers sign-in instead. Hidden when the build has no sign-in.
struct FollowingCard: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var teamSync: TeamSync
    @State private var isSigningIn = false

    static let signInReason = "Sign in to follow teams"

    /// "No teams yet", "1 team", "3 teams".
    nonisolated static func summary(count: Int) -> String {
        switch count {
        case 0: "No teams yet"
        case 1: "1 team"
        default: "\(count.formatted()) teams"
        }
    }

    /// The row's text: the count once the account's teams have loaded, since an empty
    /// list before then doesn't mean you follow none.
    nonisolated static func status(count: Int, loaded: Bool, failed: Bool) -> String {
        if loaded { return summary(count: count) }
        return failed ? "Couldn't load your teams" : "Loading…"
    }

    private var status: String {
        Self.status(count: teamSync.following.count, loaded: teamSync.hasLoaded, failed: teamSync.loadFailed)
    }

    var body: some View {
        if account.state != .unavailable {
            VStack(alignment: .leading, spacing: 4) {
                Text("FOLLOWING")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                if account.userID == nil {
                    Button {
                        isSigningIn = true
                    } label: {
                        row(Self.signInReason)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Following, \(Self.signInReason)")
                } else {
                    NavigationLink {
                        FollowingView()
                    } label: {
                        row(status)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Following, \(status)")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .sheet(isPresented: $isSigningIn) {
                SignInView(reason: Self.signInReason)
            }
        }
    }

    private func row(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.body.weight(.semibold))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// The teams you follow, newest first, each with Unfollow, and "Follow a team".
/// Pushed from Profile's Following card; pops back if the account signs out.
struct FollowingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabBarClearance) private var tabBarClearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var teamSync: TeamSync
    @State private var isFollowing = false
    /// The last team unfollowed, while its undo toast is showing.
    @State private var unfollowed: Unfollowed?

    private struct Unfollowed: Identifiable {
        let id = UUID()
        let managerID: Int
        let name: String
    }

    var body: some View {
        List {
            Section {
                Button {
                    teamSync.clearError(in: .following)
                    isFollowing = true
                } label: {
                    Label("Follow a team", systemImage: "plus")
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                }
                .themedRow()
            } footer: {
                if let error = teamSync.errors[.following], !isFollowing {
                    ErrorLine(error: error)
                }
            }

            Section {
                if !teamSync.hasLoaded {
                    if teamSync.loadFailed {
                        HStack {
                            Text("Couldn't load your teams")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry") { Task { await teamSync.refresh() } }
                        }
                        .frame(minHeight: 44)
                        .themedRow()
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .themedRow()
                    }
                } else if teamSync.following.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You're not following any teams yet")
                            .font(.body.weight(.semibold))
                        Text("Activity from the teams you follow will show on Feed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .themedRow()
                } else {
                    ForEach(teamSync.following) { team in
                        row(team)
                            .themedRow()
                    }
                }
            }
        }
        .themedScreen()
        .overlay(alignment: .bottom) {
            if let unfollowed {
                UndoToast(message: "You unfollowed \(unfollowed.name)") {
                    withAnimation { self.unfollowed = nil }
                    Task { await teamSync.refollow(unfollowed.managerID) }
                }
                .padding(.horizontal, 16)
                // The screen runs under the tab bar, so sit just above it.
                .padding(.bottom, tabBarClearance + 4)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                // As long as the Notes tab's, and a newer unfollow restarts it.
                .task(id: unfollowed.id) {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    withAnimation { self.unfollowed = nil }
                }
            }
        }
        .navigationTitle("Following")
        .navigationBarTitleDisplayMode(.inline)
        // Profile hides its bar; this page needs one for Back.
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $isFollowing) {
            FollowTeamSheet()
        }
        .onChange(of: account.userID) { _, userID in
            if userID == nil { dismiss() }
        }
    }

    private func row(_ team: AccountTeam) -> some View {
        HStack {
            Text(name(of: team))
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Button("Unfollow") {
                let name = name(of: team)
                Task {
                    guard await teamSync.unfollow(team.managerId) else { return }
                    withAnimation { unfollowed = Unfollowed(managerID: team.managerId, name: name) }
                    AccessibilityNotification.Announcement("You unfollowed \(name). Undo available.").post()
                }
            }
            .buttonStyle(.bordered)
            .disabled(teamSync.isWorking(in: .following))
        }
        .frame(minHeight: 44)
    }

    /// Until its details load; the API never sends a manager's name.
    private func name(of team: AccountTeam) -> String {
        teamSync.managers[team.managerId]?.name ?? "Team \(String(team.managerId))"
    }
}

/// Looks a team up by ID and follows it.
private struct FollowTeamSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var teamSync: TeamSync

    var body: some View {
        NavigationStack {
            ScrollView {
                LinkTeamForm(purpose: .follow, error: teamSync.errors[.following], isWorking: teamSync.isWorking(in: .following),
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
